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

const INVITE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const INVITE_CODE_LENGTH = 7;

type CallableRequest = httpsFn.CallableRequest<Record<string, unknown>>;

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

function randomInviteCode(length = INVITE_CODE_LENGTH): string {
  let code = "";
  for (let i = 0; i < length; i++) {
    const index = Math.floor(Math.random() * INVITE_CODE_CHARS.length);
    code += INVITE_CODE_CHARS.charAt(index);
  }
  return code;
}

function parseOptionalTimestamp(value: unknown, field: string): admin.firestore.Timestamp | null {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }
  if (typeof value === "number") {
    return admin.firestore.Timestamp.fromMillis(Math.trunc(value));
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return admin.firestore.Timestamp.fromDate(parsed);
    }
  }
  throw new httpsFn.HttpsError("invalid-argument", `invalid_${field}`);
}

async function ensureRoomMember(roomId: string, uid: string): Promise<admin.firestore.DocumentReference<admin.firestore.DocumentData>> {
  const roomRef = db.collection("rooms").doc(roomId);
  const memberRef = roomRef.collection("members").doc(uid);
  const memberSnap = await memberRef.get();
  if (!memberSnap.exists) {
    throw new httpsFn.HttpsError("permission-denied", "not_member");
  }
  return roomRef;
}

function timestampToIso(ts?: admin.firestore.Timestamp | null): string | null {
  if (!ts) {
    return null;
  }
  return ts.toDate().toISOString();
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

export const createInviteCode = httpsFn.onCall<Record<string, unknown>, Record<string, unknown>>(
  { region: "us-central1" },
  async (request: CallableRequest): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new httpsFn.HttpsError("unauthenticated", "auth_required");
    }

    const roomIdRaw = (request.data as Record<string, unknown> | undefined)?.["roomId"];
    const roomId = typeof roomIdRaw === "string" && roomIdRaw.trim().length > 0 ? roomIdRaw.trim() : undefined;
    if (!roomId) {
      throw new httpsFn.HttpsError("invalid-argument", "invalid_roomId");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const maxUsesRaw = data["maxUses"];
    let maxUses: number | null = null;
    if (maxUsesRaw !== undefined && maxUsesRaw !== null && maxUsesRaw !== "") {
      const parsed = Number(maxUsesRaw);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new httpsFn.HttpsError("invalid-argument", "invalid_maxUses");
      }
      maxUses = Math.trunc(parsed);
    }

    const expiresAt = parseOptionalTimestamp(data["expiresAt"], "expiresAt");
    const roomRef = await ensureRoomMember(roomId, uid);

    let code = randomInviteCode();
    let inviteRef = roomRef.collection("invites").doc(code);
    for (let i = 0; i < 5; i++) {
      const snapshot = await inviteRef.get();
      if (!snapshot.exists) {
        break;
      }
      code = randomInviteCode();
      inviteRef = roomRef.collection("invites").doc(code);
      if (i === 4) {
        throw new httpsFn.HttpsError("internal", "invite_code_collision");
      }
    }

    await inviteRef.set({
      code,
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      uses: 0,
      maxUses: maxUses ?? null,
      expiresAt: expiresAt ?? null,
    });

    const saved = await inviteRef.get();
    const savedData = saved.data() ?? {};

    return {
      code,
      invite: {
        code,
        roomId,
        createdBy: savedData["createdBy"] ?? uid,
        createdAt: timestampToIso(savedData["createdAt"] as admin.firestore.Timestamp | undefined),
        expiresAt: timestampToIso(savedData["expiresAt"] as admin.firestore.Timestamp | undefined),
        uses: savedData["uses"] ?? 0,
        maxUses: savedData["maxUses"] ?? null,
      },
    };
  }
);

export const listRoomInvites = httpsFn.onCall<Record<string, unknown>, Record<string, unknown>>(
  { region: "us-central1" },
  async (request: CallableRequest): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new httpsFn.HttpsError("unauthenticated", "auth_required");
    }

    const roomIdRaw = (request.data as Record<string, unknown> | undefined)?.["roomId"];
    const roomId = typeof roomIdRaw === "string" && roomIdRaw.trim().length > 0 ? roomIdRaw.trim() : undefined;
    if (!roomId) {
      throw new httpsFn.HttpsError("invalid-argument", "invalid_roomId");
    }

    const roomRef = await ensureRoomMember(roomId, uid);
    const invitesSnap = await roomRef.collection("invites").orderBy("createdAt", "desc").get();
    const invites = invitesSnap.docs.map((doc: admin.firestore.QueryDocumentSnapshot<admin.firestore.DocumentData>) => {
      const payload = doc.data();
      return {
        code: payload["code"] ?? doc.id,
        createdBy: payload["createdBy"] ?? null,
        createdAt: timestampToIso(payload["createdAt"] as admin.firestore.Timestamp | undefined),
        expiresAt: timestampToIso(payload["expiresAt"] as admin.firestore.Timestamp | undefined),
        uses: payload["uses"] ?? 0,
        maxUses: payload["maxUses"] ?? null,
      };
    });

    return { invites };
  }
);

export const redeemInviteCode = httpsFn.onCall<Record<string, unknown>, Record<string, unknown>>(
  { region: "us-central1" },
  async (request: CallableRequest): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new httpsFn.HttpsError("unauthenticated", "auth_required");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const codeRaw = data["code"];
    const code = typeof codeRaw === "string" && codeRaw.trim().length > 0 ? codeRaw.trim().toUpperCase() : undefined;
    if (!code) {
      throw new httpsFn.HttpsError("invalid-argument", "invalid_code");
    }

    const displayNameRaw = data["displayName"];
    const displayName = typeof displayNameRaw === "string" && displayNameRaw.trim().length > 0 ? displayNameRaw.trim() : undefined;

    const inviteQuery = await db.collectionGroup("invites").where("code", "==", code).limit(1).get();
    if (inviteQuery.empty) {
      throw new httpsFn.HttpsError("not-found", "invite_not_found");
    }

    const inviteDoc = inviteQuery.docs[0];
    const roomRef = inviteDoc.ref.parent.parent;
    if (!roomRef) {
      throw new httpsFn.HttpsError("internal", "room_not_found");
    }

    let alreadyMember = false;
    await db.runTransaction(async (tx: admin.firestore.Transaction) => {
      const freshInvite = await tx.get(inviteDoc.ref);
      if (!freshInvite.exists) {
        throw new httpsFn.HttpsError("not-found", "invite_not_found");
      }

      const payload = freshInvite.data() ?? {};
      const expiresAt = payload["expiresAt"] as admin.firestore.Timestamp | undefined;
      if (expiresAt && expiresAt.toDate().getTime() <= Date.now()) {
        throw new httpsFn.HttpsError("failed-precondition", "invite_expired");
      }

      const maxUsesValue = payload["maxUses"];
      const maxUses = typeof maxUsesValue === "number" ? Math.trunc(maxUsesValue) : null;
      const usesValue = payload["uses"];
      const uses = typeof usesValue === "number" ? usesValue : 0;
      if (maxUses !== null && uses >= maxUses) {
        throw new httpsFn.HttpsError("failed-precondition", "invite_maxed_out");
      }

      const memberRef = roomRef.collection("members").doc(uid);
      const memberSnap = await tx.get(memberRef);
      alreadyMember = memberSnap.exists;

      if (!alreadyMember) {
        tx.set(
          memberRef,
          {
            role: (memberSnap.data()?.role as string | undefined) ?? "member",
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
            displayName: displayName ?? ((request.auth?.token?.name as string | undefined) ?? "Member"),
          },
          { merge: true }
        );
        tx.set(
          roomRef,
          {
            meta: {
              members: admin.firestore.FieldValue.increment(1),
              lastMsgAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );
        tx.update(inviteDoc.ref, {
          uses: admin.firestore.FieldValue.increment(1),
        });
      }
    });

    return {
      roomId: roomRef.id,
      joined: true,
      alreadyMember,
    };
  }
);
