import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });

const stripe = new Stripe(functions.config().stripe.secret, {
  apiVersion: "2024-06-20",
});

export const ping = functions.https.onRequest((_req, res) => {
  res.status(200).json({ ok: true, ts: Date.now() });
});

export const createCheckoutSession = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

    const { priceId, customerEmail } = req.body ?? {};
    if (!priceId) return res.status(400).send("Missing priceId");

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      customer_email: customerEmail,
      currency: "eur"
    });

    res.status(200).json({ id: session.id, url: session.url });
  } catch (e) {
    console.error(e);
    res.status(500).send((e as Error).message ?? "Internal error");
  }
});
