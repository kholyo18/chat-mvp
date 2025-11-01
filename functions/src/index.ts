import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const WALLET_TYPES = new Set([
  "earn",
  "spend",
  "vip_upgrade",
  "bonus"
]);

const VIP_TIERS = new Set(["bronze", "silver", "gold", "platinum", "none"]);

export const ping = functions.https.onRequest((_req, res) => {
  res.status(200).send("ok");
});

export const walletTxn = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    const { uid, delta, type, note, vipTier } = (data ?? {}) as {
      uid?: string;
      delta?: number;
      type?: string;
      note?: string;
      vipTier?: string;
    };

    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required."
      );
    }

    if (!uid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "uid is required"
      );
    }

    const callerUid = context.auth.uid;
    const isAdmin = Boolean((context.auth.token as Record<string, unknown>).admin);
    if (callerUid !== uid && !isAdmin) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Cannot mutate another user's wallet."
      );
    }

    if (typeof delta !== "number" || Number.isNaN(delta) || !Number.isFinite(delta)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "delta must be a finite number"
      );
    }

    if (delta === 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "delta must not be zero"
      );
    }

    const normalizedType = String(type ?? "").trim();
    if (!WALLET_TYPES.has(normalizedType)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Unsupported wallet transaction type"
      );
    }

    const normalizedTier = String(vipTier ?? "").trim().toLowerCase();

    if (normalizedType === "earn" || normalizedType === "bonus") {
      if (delta <= 0) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "earn/bonus transactions require a positive delta"
        );
      }
    }

    if (normalizedType === "spend" && delta >= 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "spend transactions require a negative delta"
      );
    }

    if (normalizedType === "vip_upgrade") {
      if (delta >= 0) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "vip_upgrade transactions require a negative delta"
        );
      }

      if (!VIP_TIERS.has(normalizedTier) || normalizedTier === "none") {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "vipTier must be one of bronze|silver|gold|platinum"
        );
      }
    }

    const firestore = admin.firestore();
    const userRef = firestore.collection("users").doc(uid);
    const actor = callerUid === uid ? "user" : "system";
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    const result = await firestore.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      const userData = userSnap.exists ? (userSnap.data() as Record<string, unknown>) : {};
      const coinsRaw = userData["coins"];
      const current = typeof coinsRaw === "number" ? coinsRaw : Number(coinsRaw ?? 0);
      const next = current + delta;

      if (next < 0) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Insufficient balance"
        );
      }

      const txRef = userRef.collection("wallet_transactions").doc();
      const payload: FirebaseFirestore.DocumentData = {
        type: normalizedType,
        amount: delta,
        balanceAfter: next,
        note: note ?? "",
        createdAt: timestamp,
        actor,
      };

      transaction.set(txRef, payload);

      const userUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
        coins: next,
      };

      if (normalizedType === "vip_upgrade") {
        userUpdate["vipTier"] = normalizedTier;
        userUpdate["vipSince"] = timestamp;
      }

      transaction.set(userRef, userUpdate, { merge: true });

      return next;
    });

    return { balance: result };
  });

export { createCheckoutSession, stripeWebhook } from "./stripe";
