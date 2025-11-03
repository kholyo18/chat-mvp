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
  badge?: string;
  active?: boolean;
  type?: string;
  vip_tier?: string | null;
  coins_amount?: number;
  sort?: number;
  description?: string;
}

const VIP_RANK: Record<string, number> = {
  none: 0,
  bronze: 1,
  silver: 2,
  gold: 3,
  platinum: 4,
};

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

    const productType = (product.type ?? "").trim();
    if (!productType) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Product type is required",
      );
    }

    if (productType === "vip") {
      if (!product.vip_tier) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "VIP product missing tier",
        );
      }
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
          quantity: productType === "vip" ? 1 : qty,
        },
      ],
      success_url: `${APP_BASE_URL}/store?status=success`,
      cancel_url: `${APP_BASE_URL}/store?status=cancel`,
      metadata: {
        productId,
        uid: context.auth.uid,
        type: productType,
        vip_tier: product.vip_tier ?? "",
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
  const purchasesCollection = userRef.collection("purchases");
  const defaultPurchaseRef = purchasesCollection.doc();
  const sessionRef = firestore.collection("stripe_sessions").doc(session.id);

  await firestore.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);

    if (sessionSnap.exists && sessionSnap.data()?.fulfilled) {
      return;
    }

    const userSnap = await transaction.get(userRef);
    const userData = userSnap.exists
      ? (userSnap.data() as Record<string, unknown>)
      : {};

    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    let purchaseRef = defaultPurchaseRef;
    const existingPurchaseId = sessionSnap.data()?.purchaseId;
    if (sessionSnap.exists && typeof existingPurchaseId === "string" && existingPurchaseId) {
      purchaseRef = purchasesCollection.doc(existingPurchaseId);
    }
    const normalizedType = (product.type ?? "").trim();

    const purchaseData: FirebaseFirestore.DocumentData = {
      productId,
      amount_cents: product.price_cents ?? 0,
      currency: (product.currency ?? "USD").toUpperCase(),
      status: "paid",
      stripe_checkout_session: session.id,
      createdAt: timestamp,
      fulfilledAt: timestamp,
      type: normalizedType,
      vipTier: product.vip_tier ?? null,
    };

    const userUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
    let vipSkipReason: "already-at-tier" | "higher-tier-exists" | null = null;

    if (normalizedType === "coins" && (product.coins_amount ?? 0) > 0) {
      const increment = Number(product.coins_amount ?? 0);
      userUpdate["coins"] = admin.firestore.FieldValue.increment(increment);
    }

    if (normalizedType === "vip" && product.vip_tier) {
      const targetTier = String(product.vip_tier ?? "").toLowerCase();
      const currentTierRaw = String(userData["vipTier"] ?? "").toLowerCase();
      const targetRank = VIP_RANK[targetTier] ?? 0;
      const currentRank = VIP_RANK[currentTierRaw] ?? 0;

      if (targetRank === 0) {
        throw new Error(`Invalid VIP tier ${product.vip_tier} for product ${productId}`);
      }

      if (targetRank > currentRank) {
        userUpdate["vipTier"] = targetTier;
        userUpdate["vipSince"] = timestamp;
        userUpdate["vipNotice"] = admin.firestore.FieldValue.delete();
        userUpdate["vipNoticeAt"] = admin.firestore.FieldValue.delete();
      } else {
        vipSkipReason = targetRank === currentRank ? "already-at-tier" : "higher-tier-exists";
        userUpdate["vipNotice"] = "higher-tier-exists";
        userUpdate["vipNoticeAt"] = timestamp;
      }
    }

    if (normalizedType === "feature" || normalizedType === "theme") {
      userUpdate[`entitlements.${productId}`] = true;
    }

    if (vipSkipReason) {
      purchaseData.note = vipSkipReason;
    }

    transaction.set(purchaseRef, purchaseData, { merge: true });

    if (Object.keys(userUpdate).length > 0) {
      transaction.set(userRef, userUpdate, { merge: true });
    }

    const sessionData: FirebaseFirestore.DocumentData = {
      fulfilled: true,
      productId,
      uid,
      purchaseId: purchaseRef.id,
      stripe_checkout_session: session.id,
      updatedAt: timestamp,
      type: normalizedType,
    };

    if (!sessionSnap.exists) {
      sessionData.createdAt = timestamp;
    }

    transaction.set(sessionRef, sessionData, { merge: true });
  });
}
