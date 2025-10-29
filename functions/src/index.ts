import { onRequest, defineSecret } from "firebase-functions/v2/https";
import type { Request, Response } from "express";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import Stripe from "stripe";
import fetch from "node-fetch";

initializeApp();
const db = getFirestore();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

// (coins -> EUR cents)
const ALLOWED_PACKS: Record<number, number> = {
  100: 1_00,
  550: 4_00,
  1500: 9_00
};

// ============ Create Checkout Session ============
export const createCheckoutSession = onRequest(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
  async (req: Request, res: Response) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

      const { metadata, coins, amount_eur, success_url, cancel_url } = req.body || {};
      const uid: string | undefined = metadata?.uid;
      if (!uid || !coins || !success_url || !cancel_url)
        return res.status(400).json({ error: "missing fields (uid/coins/success_url/cancel_url)" });

      const expected = ALLOWED_PACKS[Number(coins)];
      if (!expected) return res.status(400).json({ error: "invalid pack" });

      if (typeof amount_eur === "number" && Math.round(amount_eur * 100) !== expected)
        return res.status(400).json({ error: "amount mismatch" });

      const stripe = new Stripe(STRIPE_SECRET_KEY.value());
      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        success_url,
        cancel_url,
        metadata: { uid, coins: String(coins) },
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: "eur",
              unit_amount: expected,
              product_data: { name: `${coins} coins` }
            }
          }
        ]
      });

      res.status(200).json({ url: session.url });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: (e as any)?.message || "internal" });
    }
  }
);

// ============ Stripe Webhook (credit + notification) ============
export const stripeWebhook = onRequest(
  { region: "us-central1", secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET], cors: true },
  async (req: Request, res: Response) => {
    const sig = req.get("stripe-signature");
    if (!sig) return res.status(400).send("Missing Stripe-Signature header");

    try {
      const stripe = new Stripe(STRIPE_SECRET_KEY.value());
      const event = stripe.webhooks.constructEvent(
        req.rawBody, sig, STRIPE_WEBHOOK_SECRET.value()
      );

      if (event.type === "checkout.session.completed") {
        const session = event.data.object as Stripe.Checkout.Session;
        const uid = session.metadata?.uid;
        const coinsStr = session.metadata?.coins;
        const paid = session.payment_status === "paid";

        if (uid && coinsStr && paid) {
          const coins = parseInt(coinsStr, 10);

          // 1) زد الرصيد
          await db.collection("users").doc(uid).set(
            { coins: FieldValue.increment(coins) },
            { merge: true }
          );

          // 2) إشعار داخل Firestore (subcollection)
          await db
            .collection("users").doc(uid)
            .collection("notifications").add({
              type: "coins_topup",
              title: "تم شحن رصيدك",
              body: `تمت إضافة ${coins} coins إلى محفظتك بنجاح.`,
              createdAt: Timestamp.now(),
              read: false,
              provider: "stripe",
              eventId: event.id
            });

          console.log(`✅ Added ${coins} coins & wrote notification for uid=${uid}`);
        }
      }

      res.status(200).send("ok");
    } catch (err: any) {
      console.error("⚠️ Webhook error:", err?.message);
      res.status(400).send(`Webhook Error: ${err?.message}`);
    }
  }
);

// ============ (اختياري) Ping endpoint بسيط للصحة ============
export const coinsConfig = onRequest(
  { region: "us-central1" },
  async (_req: Request, res: Response) => {
    res.status(200).json({ ok: true, packs: Object.keys(ALLOWED_PACKS) });
  }
);
