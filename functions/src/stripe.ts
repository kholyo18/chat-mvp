import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import Stripe from "stripe";

const STRIPE_SECRET_KEY =
  process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret || "";
const STRIPE_PUBLISHABLE_KEY =
  process.env.STRIPE_PUBLISHABLE_KEY || functions.config().stripe?.publishable;
const STRIPE_WEBHOOK_SECRET =
  process.env.STRIPE_WEBHOOK_SECRET || functions.config().stripe?.webhook || "";
const APP_BASE_URL =
  process.env.APP_BASE_URL || functions.config().app?.base_url || "";

const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2023-08-16" });

interface StoreProductDoc {
  title?: string;
  subtitle?: string;
  price_cents?: number;
  currency?: string;
  stripe_price_id?: string;
  icon?: string;
  active?: boolean;
  type?: string;
  vip_tier?: string | null;
  coins_amount?: number;
  sort?: number;
  description?: string;
}

export const createCheckoutSession = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }

    const { productId, quantity } = (data ?? {}) as {
      productId?: string;
      quantity?: number;
    };

    if (!productId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "productId is required",
      );
    }

    const qty = quantity && quantity > 0 ? quantity : 1;

    const productSnap = await admin
      .firestore()
      .collection("store_products")
      .doc(productId)
      .get();

    if (!productSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Product not found",
      );
    }

    const product = productSnap.data() as StoreProductDoc;
    if (!product.active) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Product is not available",
      );
    }

    if (!product.stripe_price_id) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Product is misconfigured",
      );
    }

    if (!APP_BASE_URL) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "APP_BASE_URL is not configured",
      );
    }

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [
        {
          price: product.stripe_price_id,
          quantity: qty,
        },
      ],
      success_url: `${APP_BASE_URL}/store?status=success`,
      cancel_url: `${APP_BASE_URL}/store?status=cancel`,
      metadata: {
        productId,
        uid: context.auth.uid,
      },
    });

    return { url: session.url, sessionId: session.id, publishableKey: STRIPE_PUBLISHABLE_KEY };
  });

export const stripeWebhook = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const signature = req.headers["stripe-signature"];
    if (!signature || Array.isArray(signature)) {
      res.status(400).send("Missing Stripe signature");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        signature,
        STRIPE_WEBHOOK_SECRET
      );
    } catch (err: any) {
      console.error("Webhook signature verification failed", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const metadata = session.metadata ?? {};
      const uid = metadata.uid;
      const productId = metadata.productId;

      if (!uid || !productId) {
        console.error("Missing uid or productId in session metadata", session.id);
        res.status(200).send("ok");
        return;
      }

      try {
        await handleCheckoutCompleted({ session, uid, productId });
      } catch (error) {
        console.error("Checkout completion handling failed", error);
      }
    }

    res.status(200).send("ok");
  });

async function handleCheckoutCompleted(args: {
  session: Stripe.Checkout.Session;
  uid: string;
  productId: string;
}): Promise<void> {
  const { session, uid, productId } = args;
  const firestore = admin.firestore();
  const productSnap = await firestore
    .collection("store_products")
    .doc(productId)
    .get();

  if (!productSnap.exists) {
    throw new Error(`Product ${productId} not found for checkout ${session.id}`);
  }

  const product = productSnap.data() as StoreProductDoc;
  if (!product.active) {
    throw new Error(`Product ${productId} inactive`);
  }

  const userRef = firestore.collection("users").doc(uid);
  const purchaseRef = userRef.collection("purchases").doc(session.id);

  await firestore.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const purchaseData: FirebaseFirestore.DocumentData = {
      productId,
      amount_cents: product.price_cents ?? 0,
      currency: (product.currency ?? "USD").toUpperCase(),
      status: "paid",
      stripe_checkout_session: session.id,
      createdAt: timestamp,
      fulfilledAt: timestamp,
    };

    const userUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};

    if (product.type === "coins" && (product.coins_amount ?? 0) > 0) {
      const increment = Number(product.coins_amount ?? 0);
      userUpdate["coins"] = admin.firestore.FieldValue.increment(increment);
    }

    if (product.type === "vip" && product.vip_tier) {
      userUpdate["vipTier"] = product.vip_tier;
      userUpdate["vipSince"] = timestamp;
    }

    if (product.type === "feature" || product.type === "theme") {
      userUpdate[`entitlements.${productId}`] = true;
    }

    transaction.set(purchaseRef, purchaseData, { merge: true });
    if (Object.keys(userUpdate).length > 0) {
      transaction.set(userRef, userUpdate, { merge: true });
    }
  });
}
