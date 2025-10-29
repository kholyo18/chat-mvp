import * as httpsFn from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();
const db = admin.firestore();

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY as string;
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET as string;

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export interface CoinPack {
  id: string;
  label: string;
  coins: number;
  price: number;
}

export const COIN_PACKS: CoinPack[] = [
  { id: "coins_100", label: "100 Coins", coins: 100, price: 1.0 },
  { id: "coins_500", label: "500 Coins", coins: 500, price: 4.0 },
  { id: "coins_1500", label: "1500 Coins", coins: 1500, price: 9.0 }
];

const PACK_BY_ID = new Map<string, CoinPack>();
const PACK_BY_COINS = new Map<number, CoinPack>();

for (const pack of COIN_PACKS) {
  PACK_BY_ID.set(pack.id, pack);
  PACK_BY_COINS.set(pack.coins, pack);
}

const DEFAULT_RATE = 100; // coins per currency unit
const DEFAULT_CURRENCY = "EUR";
const DEFAULT_DAILY_LIMIT = 5000;

function getPack(options: { coins?: number; packageId?: string | null }): CoinPack | undefined {
  if (options.packageId) {
    const pack = PACK_BY_ID.get(options.packageId);
    if (pack) {
      return pack;
    }
  }
  if (typeof options.coins === "number") {
    return PACK_BY_COINS.get(options.coins);
  }
  return undefined;
}

async function verifyAuth(req: httpsFn.Request): Promise<string> {
  const authHeader = req.get("authorization") ?? req.get("Authorization") ?? "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new HttpError(401, "unauthorized");
  }
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded.uid;
  } catch (error) {
    console.error("ID token verification failed", error);
    throw new HttpError(401, "unauthorized");
  }
}

function parseUrl(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `invalid_${field}`);
  }
  try {
    const url = new URL(value);
    return url.toString();
  } catch {
    throw new HttpError(400, `invalid_${field}`);
  }
}

function coinsToAmountCents(coins: number, pack?: CoinPack): number {
  if (pack) {
    return Math.max(1, Math.round(pack.price * 100));
  }
  if (coins <= 0) {
    return 0;
  }
  const estimated = coins / DEFAULT_RATE;
  return Math.max(1, Math.round(estimated * 100));
}

export const createCheckoutSession = httpsFn.onRequest(async (req: httpsFn.Request, res: httpsFn.Response): Promise<void> => {
  try {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    if (!STRIPE_SECRET_KEY) {
      throw new HttpError(500, "stripe_not_configured");
    }

    const body = (req.body || {}) as Record<string, unknown>;
    const coinsRaw = body["coins"];
    const packageId = typeof body["packageId"] === "string" ? body["packageId"] : undefined;
    const successUrl = parseUrl(body["successUrl"], "successUrl");
    const cancelUrl = parseUrl(body["cancelUrl"], "cancelUrl");
    const coins = typeof coinsRaw === "number" ? Math.trunc(coinsRaw) : Number(coinsRaw);
    if (!Number.isFinite(coins) || coins <= 0) {
      throw new HttpError(400, "invalid_coins");
    }

    let uid = typeof body["uid"] === "string" ? body["uid"] : undefined;
    if (!uid) {
      try {
        uid = await verifyAuth(req);
      } catch (authError) {
        const metadata = body["metadata"] as Record<string, unknown> | undefined;
        if (metadata && typeof metadata.uid === "string") {
          uid = metadata.uid;
        } else {
          throw authError;
        }
      }
    }

    const amountEurRaw = body["amount_eur"];
    const providedAmountCents =
      typeof amountEurRaw === "number" ? Math.max(0, Math.round(amountEurRaw * 100)) : undefined;
    const pack = getPack({ coins, packageId });
    if (pack && providedAmountCents && providedAmountCents !== Math.round(pack.price * 100)) {
      throw new HttpError(400, "amount_mismatch");
    }
    let amountCents = coinsToAmountCents(coins, pack);
    if (!pack && providedAmountCents) {
      amountCents = providedAmountCents;
    }
    if (!uid) {
      throw new HttpError(401, "unauthorized");
    }
    if (!Number.isFinite(amountCents) || amountCents <= 0) {
      throw new HttpError(400, "invalid_amount");
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        uid: uid ?? "",
        coins: String(coins),
        packageId: pack?.id ?? packageId ?? "manual",
      },
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: DEFAULT_CURRENCY.toLowerCase(),
            unit_amount: amountCents,
            product_data: {
              name: pack?.label ?? `${coins} Coins`,
            },
          },
        },
      ],
    });

    res.status(200).json({
      ok: true,
      url: session.url,
      pack: pack
        ? { id: pack.id, coins: pack.coins, price: pack.price }
        : { id: packageId ?? "manual", coins, price: amountCents / 100 },
    });
  } catch (e: any) {
    if (e instanceof HttpError) {
      res.status(e.status).json({ error: e.message });
      return;
    }
    console.error(e);
    res.status(500).json({ error: e?.message || "internal" });
  }
});

export const stripeWebhook = httpsFn.onRequest(async (req: httpsFn.Request, res: httpsFn.Response): Promise<void> => {
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

export const coinsConfig = httpsFn.onRequest((_req: httpsFn.Request, res: httpsFn.Response): void => {
  res.status(200).json({
    ok: true,
    currency: DEFAULT_CURRENCY,
    rate: DEFAULT_RATE,
    dailyLimitCoins: DEFAULT_DAILY_LIMIT,
    playSkus: COIN_PACKS.map((pack) => pack.id),
    packs: COIN_PACKS.map((pack) => ({
      id: pack.id,
      label: pack.label,
      coins: pack.coins,
      price: pack.price,
    })),
  });
});
