import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();

const STRIPE_SECRET =
  process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret || "";

const stripe = new Stripe(STRIPE_SECRET, { apiVersion: "2023-10-16" });

export const ping = functions.https.onRequest((_req, res) => {
  res.status(200).send("ok");
});

export const createCheckoutSession = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const { priceId } = (req.body ?? {}) as { priceId?: string };
    if (!priceId) {
      res.status(400).send("Missing priceId");
      return;
    }

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel"
    });

    res.status(200).json({ id: session.id, url: session.url });
    return;
  } catch (e: any) {
    console.error(e);
    res.status(500).send(e?.message ?? "Internal error");
    return;
  }
});
