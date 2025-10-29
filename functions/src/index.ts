import * as httpsFn from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();
const db = admin.firestore();

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY as string;
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET as string;

const ALLOWED_PACKS: Record<number, number> = { 100: 1_00, 550: 4_00, 1500: 9_00 };

export const createCheckoutSession = httpsFn.onRequest(async (req, res): Promise<void> => {
  try {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }
    const { metadata, coins, amount_eur, success_url, cancel_url } = (req.body || {});
    const uid = metadata?.uid as string | undefined;
    if (!uid || !coins || !success_url || !cancel_url) { res.status(400).json({ error: "missing fields" }); return; }
    const expected = ALLOWED_PACKS[Number(coins)];
    if (!expected) { res.status(400).json({ error: "invalid pack" }); return; }
    if (typeof amount_eur === "number" && Math.round(amount_eur * 100) !== expected) { res.status(400).json({ error: "amount mismatch" }); return; }

    const stripe = new Stripe(STRIPE_SECRET_KEY);
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      success_url, cancel_url,
      metadata: { uid, coins: String(coins) },
      line_items: [{
        quantity: 1,
        price_data: { currency: "eur", unit_amount: expected, product_data: { name: `${coins} coins` } }
      }]
    });
    res.status(200).json({ url: session.url });
  } catch (e: any) { console.error(e); res.status(500).json({ error: e.message || "internal" }); }
});

export const stripeWebhook = httpsFn.onRequest(async (req, res): Promise<void> => {
  const sig = req.headers["stripe-signature"] as string | undefined;
  if (!sig) { res.status(400).send("Missing Stripe-Signature header"); return; }
  try {
    const stripe = new Stripe(STRIPE_SECRET_KEY);
    const event = stripe.webhooks.constructEvent((req as any).rawBody, sig, STRIPE_WEBHOOK_SECRET);
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const uid = session.metadata?.uid;
      const coinsStr = session.metadata?.coins;
      const paid = session.payment_status === "paid";
      if (uid && coinsStr && paid) {
        const coins = parseInt(coinsStr, 10);
        await db.collection("users").doc(uid).set(
          { coins: admin.firestore.FieldValue.increment(coins) },
          { merge: true }
        );
        await db.collection("users").doc(uid).collection("notifications").add({
          type: "coins_topup",
          title: "تم شحن رصيدك",
          body: `تمت إضافة ${coins} coins إلى محفظتك.`,
          createdAt: admin.firestore.Timestamp.now(),
          read: false,
          provider: "stripe",
          eventId: event.id
        });
        console.log(`Added ${coins} coins for ${uid}`);
      }
    }
    res.status(200).send("ok");
  } catch (err: any) { console.error("Webhook error:", err.message); res.status(400).send(`Webhook Error: ${err.message}`); }
});

export const coinsConfig = httpsFn.onRequest((_req, res): void => {
  res.status(200).json({ ok: true, packs: Object.keys(ALLOWED_PACKS) });
});
