const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Stripe = require('stripe');
const cors = require('cors')({ origin: true });
const { google } = require('googleapis');

admin.initializeApp();

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const stripeSecret = process.env.STRIPE_SECRET_KEY || '';
const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET || '';
const stripe = stripeSecret
  ? new Stripe(stripeSecret, { apiVersion: '2024-06-20' })
  : null;

const GOOGLE_PLAY_PACKAGE_NAME = process.env.GOOGLE_PLAY_PACKAGE_NAME || '';
const PLAY_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || '';

const COINS_CONFIG_REF = db.collection('config').doc('coins');

function coinsFromSku(productId) {
  if (!productId) {
    return 0;
  }
  const digits = (productId.match(/\d+/g) || []).join('');
  return digits ? parseInt(digits, 10) : 0;
}

function estimateFiat(rate, coins) {
  if (!rate || rate <= 0) {
    return 0;
  }
  return Number((coins / rate).toFixed(2));
}

async function getCoinsConfig() {
  const snap = await COINS_CONFIG_REF.get();
  if (!snap.exists) {
    throw new Error('coins_config_missing');
  }
  const data = snap.data() || {};
  return {
    rate: typeof data.rate === 'number' ? data.rate : Number(data.rate) || 100,
    currency: typeof data.currency === 'string' ? data.currency : 'USD',
    dailyLimitCoins:
      typeof data.dailyLimitCoins === 'number'
        ? data.dailyLimitCoins
        : Number(data.dailyLimitCoins) || 0,
    playSkus: Array.isArray(data.playSkus) ? data.playSkus : [],
  };
}

async function getCompletedCoinsToday(uid) {
  const now = new Date();
  const startOfDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const snapshot = await db
    .collection('payments')
    .where('uid', '==', uid)
    .where('status', '==', 'completed')
    .where('completedAt', '>=', admin.firestore.Timestamp.fromDate(startOfDay))
    .get();
  let total = 0;
  snapshot.forEach((doc) => {
    const value = doc.get('coins');
    if (typeof value === 'number' && Number.isFinite(value)) {
      total += value;
    }
  });
  return total;
}

async function verifyAuth(req) {
  const authHeader = req.headers.authorization || '';
  const match = authHeader.match(/^Bearer\s+(.*)$/i);
  if (!match) {
    const error = new Error('unauthorized');
    error.status = 401;
    throw error;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch (err) {
    functions.logger.warn('ID token verification failed', err);
    const error = new Error('unauthorized');
    error.status = 401;
    throw error;
  }
}

function sendError(res, error, status = 500, extra = {}) {
  const message = typeof error === 'string' ? error : error.message || 'internal_error';
  functions.logger.error('Request failed', message, error);
  res.status(status).json({ error: message, ...extra });
}

let androidPublisherClient = null;
async function getAndroidPublisher() {
  if (androidPublisherClient) {
    return androidPublisherClient;
  }
  if (!PLAY_SERVICE_ACCOUNT_JSON) {
    throw new Error('google_play_service_account_missing');
  }
  const credentials = JSON.parse(PLAY_SERVICE_ACCOUNT_JSON);
  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });
  const authClient = await auth.getClient();
  androidPublisherClient = google.androidpublisher({
    version: 'v3',
    auth: authClient,
  });
  return androidPublisherClient;
}

async function finalizePayment({
  paymentId,
  provider,
  coins,
  uid,
  fiatAmount,
  currency,
  metaUpdates = {},
}) {
  if (!Number.isFinite(coins) || coins <= 0) {
    throw new Error('invalid_coin_amount');
  }
  const paymentRef = db.collection('payments').doc(paymentId);
  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    if (!paymentSnap.exists) {
      throw new Error('payment_not_found');
    }
    const paymentData = paymentSnap.data() || {};
    if (paymentData.status === 'completed') {
      return;
    }
    const userRef = db.collection('users').doc(uid);
    const userSnap = await tx.get(userRef);
    const currentCoins =
      userSnap.exists && typeof userSnap.data().coins === 'number'
        ? userSnap.data().coins
        : 0;
    const nextCoins = currentCoins + coins;
    if (userSnap.exists) {
      tx.update(userRef, { coins: nextCoins });
    } else {
      tx.set(userRef, { coins: nextCoins }, { merge: true });
    }
    const walletRef = db.collection('wallet').doc(uid).collection('tx').doc();
    tx.set(walletRef, {
      type: 'purchase',
      amount: coins,
      balanceAfter: nextCoins,
      provider,
      paymentId,
      fiatAmount: fiatAmount ?? paymentData.fiatAmount ?? null,
      currency: currency || paymentData.currency || 'USD',
      createdAt: FieldValue.serverTimestamp(),
    });
    const updates = {
      status: 'completed',
      completedAt: FieldValue.serverTimestamp(),
      coins,
    };
    if (fiatAmount != null) {
      updates.fiatAmount = fiatAmount;
    }
    if (currency) {
      updates.currency = currency;
    }
    const metaUpdateFields = {};
    Object.entries(metaUpdates).forEach(([key, value]) => {
      metaUpdateFields[`meta.${key}`] = value;
    });
    tx.update(paymentRef, { ...updates, ...metaUpdateFields });
  });
}

exports.coinsConfig = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== 'GET') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    try {
      const config = await getCoinsConfig();
      res.json(config);
    } catch (err) {
      sendError(res, err);
    }
  });
});

exports.createCheckoutSession = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    if (!stripe) {
      sendError(res, 'stripe_not_configured', 500);
      return;
    }
    try {
      const decoded = await verifyAuth(req);
      const uid = decoded.uid;
      const { coins, successUrl, cancelUrl, packageId } = req.body || {};
      if (!Number.isInteger(coins) || coins <= 0) {
        sendError(res, 'invalid_coins', 400);
        return;
      }
      let success;
      let cancel;
      try {
        success = new URL(successUrl);
        cancel = new URL(cancelUrl);
      } catch (err) {
        sendError(res, 'invalid_redirect_url', 400);
        return;
      }
      const config = await getCoinsConfig();
      if (!config.rate || config.rate <= 0) {
        sendError(res, 'invalid_rate', 500);
        return;
      }
      const completedToday = await getCompletedCoinsToday(uid);
      if (
        config.dailyLimitCoins > 0 &&
        completedToday + coins > config.dailyLimitCoins
      ) {
        const remaining = Math.max(0, config.dailyLimitCoins - completedToday);
        sendError(res, 'daily_limit_reached', 403, { remaining });
        return;
      }
      const fiatAmount = estimateFiat(config.rate, coins);
      const unitAmount = Math.max(1, Math.round(fiatAmount * 100));
      const paymentRef = db.collection('payments').doc();
      const session = await stripe.checkout.sessions.create({
        mode: 'payment',
        success_url: success.toString(),
        cancel_url: cancel.toString(),
        metadata: {
          paymentId: paymentRef.id,
          uid,
          coins: String(coins),
          packageId: packageId || '',
        },
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: (config.currency || 'USD').toLowerCase(),
              product_data: {
                name: `${coins} Coins`,
              },
              unit_amount: unitAmount,
            },
          },
        ],
      });
      await paymentRef.set({
        uid,
        provider: 'stripe',
        coins,
        fiatAmount,
        currency: config.currency || 'USD',
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
        completedAt: null,
        packageId: packageId || null,
        meta: {
          stripeSessionId: session.id,
          stripePaymentIntent: session.payment_intent || null,
          playPurchaseToken: null,
          playProductId: null,
          playOrderId: null,
        },
      });
      res.json({ url: session.url, paymentId: paymentRef.id });
    } catch (err) {
      if (err.status) {
        sendError(res, err, err.status);
      } else {
        sendError(res, err);
      }
    }
  });
});

exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }
  if (!stripe || !stripeWebhookSecret) {
    res.status(500).send('Stripe not configured');
    return;
  }
  const signature = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, signature, stripeWebhookSecret);
  } catch (err) {
    functions.logger.error('Stripe webhook signature verification failed', err);
    res.status(400).send('Webhook Error');
    return;
  }

  try {
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const paymentId = session.metadata?.paymentId;
      const uid = session.metadata?.uid;
      if (paymentId && uid) {
        const amount = session.amount_total != null ? session.amount_total / 100 : null;
        const currency = session.currency ? session.currency.toUpperCase() : undefined;
        const paymentRef = db.collection('payments').doc(paymentId);
        const paymentSnap = await paymentRef.get();
        if (!paymentSnap.exists) {
          functions.logger.warn('Payment doc missing for session', paymentId);
        } else {
          const coins = paymentSnap.get('coins');
          if (typeof coins !== 'number' || !Number.isFinite(coins)) {
            functions.logger.error('Invalid coin value on payment', paymentId);
          } else {
            await finalizePayment({
              paymentId,
              provider: 'stripe',
              coins,
              uid,
              fiatAmount: amount,
              currency,
              metaUpdates: {
                stripeSessionId: session.id,
                stripePaymentIntent: session.payment_intent || null,
              },
            });
          }
        }
      }
    } else if (event.type === 'payment_intent.succeeded') {
      const intent = event.data.object;
      const paymentId = intent.metadata?.paymentId;
      const uid = intent.metadata?.uid;
      if (paymentId && uid) {
        const amount = intent.amount_received != null ? intent.amount_received / 100 : null;
        const currency = intent.currency ? intent.currency.toUpperCase() : undefined;
        const paymentSnap = await db.collection('payments').doc(paymentId).get();
        if (paymentSnap.exists) {
          const coins = paymentSnap.get('coins');
          if (typeof coins !== 'number' || !Number.isFinite(coins)) {
            functions.logger.error('Invalid coin value on payment', paymentId);
          } else {
            await finalizePayment({
              paymentId,
              provider: 'stripe',
              coins,
              uid,
              fiatAmount: amount,
              currency,
              metaUpdates: {
                stripePaymentIntent: intent.id,
              },
            });
          }
        }
      }
    }
    res.json({ received: true });
  } catch (err) {
    functions.logger.error('Stripe webhook handling error', err);
    res.status(500).send('Webhook handler failed');
  }
});

exports.verifyPlayPurchase = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }
    if (!GOOGLE_PLAY_PACKAGE_NAME) {
      sendError(res, 'google_play_package_not_configured', 500);
      return;
    }
    try {
      const decoded = await verifyAuth(req);
      const uid = decoded.uid;
      const { purchaseToken, productId, orderId } = req.body || {};
      if (!purchaseToken || !productId) {
        sendError(res, 'invalid_purchase_payload', 400);
        return;
      }
      const config = await getCoinsConfig();
      const coins = coinsFromSku(productId);
      if (!coins) {
        sendError(res, 'unknown_sku', 400);
        return;
      }
      const existing = await db
        .collection('payments')
        .where('meta.playPurchaseToken', '==', purchaseToken)
        .limit(1)
        .get();
      if (!existing.empty) {
        const doc = existing.docs[0];
        const data = doc.data();
        if (data.uid !== uid) {
          sendError(res, 'purchase_already_claimed', 409);
          return;
        }
        if (data.status === 'completed') {
          res.json({ status: 'ok', coins: data.coins || coins });
          return;
        }
      }
      const completedToday = await getCompletedCoinsToday(uid);
      if (
        config.dailyLimitCoins > 0 &&
        completedToday + coins > config.dailyLimitCoins
      ) {
        const remaining = Math.max(0, config.dailyLimitCoins - completedToday);
        sendError(res, 'daily_limit_reached', 403, { remaining });
        return;
      }
      const publisher = await getAndroidPublisher();
      const response = await publisher.purchases.products.get({
        packageName: GOOGLE_PLAY_PACKAGE_NAME,
        productId,
        token: purchaseToken,
      });
      const purchase = response.data || {};
      if (purchase.purchaseState !== 0) {
        sendError(res, 'purchase_not_completed', 400);
        return;
      }
      const paymentRef = existing.empty
        ? db.collection('payments').doc()
        : existing.docs[0].ref;
      await db.runTransaction(async (tx) => {
        const paymentSnap = await tx.get(paymentRef);
        if (paymentSnap.exists && paymentSnap.data().status === 'completed') {
          return;
        }
        if (!paymentSnap.exists) {
          tx.set(paymentRef, {
            uid,
            provider: 'play',
            coins,
            fiatAmount: estimateFiat(config.rate, coins),
            currency: config.currency || 'USD',
            status: 'pending',
            createdAt: FieldValue.serverTimestamp(),
            completedAt: null,
            packageId: productId,
            meta: {
              playPurchaseToken: purchaseToken,
              playProductId: productId,
              playOrderId: orderId || purchase.orderId || null,
              stripeSessionId: null,
              stripePaymentIntent: null,
            },
          });
        }
        const userRef = db.collection('users').doc(uid);
        const userSnap = await tx.get(userRef);
        const currentCoins =
          userSnap.exists && typeof userSnap.data().coins === 'number'
            ? userSnap.data().coins
            : 0;
        const nextCoins = currentCoins + coins;
        if (userSnap.exists) {
          tx.update(userRef, { coins: nextCoins });
        } else {
          tx.set(userRef, { coins: nextCoins }, { merge: true });
        }
        const walletRef = db.collection('wallet').doc(uid).collection('tx').doc();
        tx.set(walletRef, {
          type: 'purchase',
          amount: coins,
          balanceAfter: nextCoins,
          provider: 'play',
          paymentId: paymentRef.id,
          fiatAmount: estimateFiat(config.rate, coins),
          currency: config.currency || 'USD',
          createdAt: FieldValue.serverTimestamp(),
        });
        tx.update(paymentRef, {
          status: 'completed',
          completedAt: FieldValue.serverTimestamp(),
          coins,
          fiatAmount: estimateFiat(config.rate, coins),
          currency: config.currency || 'USD',
          'meta.playPurchaseToken': purchaseToken,
          'meta.playProductId': productId,
          'meta.playOrderId': orderId || purchase.orderId || null,
        });
      });

      try {
        await publisher.purchases.products.consume({
          packageName: GOOGLE_PLAY_PACKAGE_NAME,
          productId,
          token: purchaseToken,
        });
      } catch (consumeErr) {
        functions.logger.warn('Failed to consume Play purchase', consumeErr);
      }

      try {
        await publisher.purchases.products.acknowledge({
          packageName: GOOGLE_PLAY_PACKAGE_NAME,
          productId,
          token: purchaseToken,
          requestBody: {
            developerPayload: orderId || purchase.orderId || '',
          },
        });
      } catch (ackErr) {
        functions.logger.warn('Failed to acknowledge Play purchase', ackErr);
      }

      res.json({ status: 'ok', coins });
    } catch (err) {
      if (err.status) {
        sendError(res, err, err.status);
      } else {
        sendError(res, err);
      }
    }
  });
});
