# Chat MVP

This repository contains the Flutter client and Firebase resources for the chat
MVP application. The app ships with a server-backed wallet (coins, VIP tiers,
and transaction history) plus verified coin purchases through Google Play
Billing and Stripe Checkout.

## Prerequisites

- Flutter 3.24+ and Dart 3.3+
- A configured Firebase project (Firestore, Authentication, Cloud Functions)
- Node.js 20+ for deploying Cloud Functions
- Stripe account (Checkout + Webhooks)
- Google Play Console access with a service account that can access the
  Android Publisher API

## Firebase configuration

1. Create the following Firestore document to describe coin pricing and limits:

   ```text
   config/coins => {
     rate: 100,             // coins per 1 currency unit
     currency: "USD",      // Stripe/Play currency
     dailyLimitCoins: 5000, // max coins per user per day
     playSkus: ["coins_100", "coins_250", "coins_600", "coins_1500"]
   }
   ```

2. Deploy the Firestore security rules and composite index:

   ```bash
   firebase deploy --only firestore:rules
   firebase deploy --only firestore:indexes
   ```

   The rules lock coin mutations to server-side functions and restrict wallet
   and payment collections to read-only access from the client.

## Wallet & VIP data model

The in-app wallet stores balances on the user document and keeps a full
transaction ledger under the same user. The shape is:

```text
users/{uid} {
  coins: number,
  vipTier: "none" | "bronze" | "silver" | "gold" | "platinum",
  vipSince: Timestamp | null,
  ...other profile fields
}

users/{uid}/wallet_transactions/{tid} {
  type: "earn" | "spend" | "vip_upgrade" | "bonus",
  amount: number,            // positive for earns, negative for spends
  balanceAfter: number,      // post-transaction balance snapshot
  note: string,
  createdAt: server timestamp,
  actor: "user" | "system"
}
```

Clients may only read these documents. All mutations flow through the callable
Cloud Function described below or through privileged server tooling.

### Callable Function: `walletTxn`

`functions/src/index.ts` exposes a `walletTxn` callable. It atomically:

1. Validates the request payload `{ uid, delta, type, note, vipTier? }`.
2. Reads the user's current balance.
3. Aborts if the resulting balance would be negative.
4. Appends a transaction document under `users/{uid}/wallet_transactions`.
5. Updates `users/{uid}` with the new `coins` value and, for `vip_upgrade`, the
   new `vipTier` and `vipSince` timestamp.

The function returns `{ balance: <nextBalance> }`. Clients should prefer this
callable, but the Flutter `WalletService` automatically falls back to a Firestore
transaction when the function is unavailable (for example on emulators).

### Seeding demo coins

During development you can credit coins by invoking the callable from the
Firebase CLI:

```bash
firebase functions:call walletTxn --data '{"uid":"<USER_ID>","delta":500,"type":"earn","note":"dev seed"}'
```

Alternatively, run the Flutter app and use the Wallet page's "Earn coins"
shortcuts to trigger the same flow.

## Cloud Functions

All payment-related endpoints live under `functions/`. Install dependencies and
follow the deployment instructions in [`functions/README.md`](functions/README.md).

Required environment variables for production deployments:

| Variable | Purpose |
| --- | --- |
| `STRIPE_SECRET_KEY` | Secret key used to create Stripe Checkout sessions. |
| `STRIPE_WEBHOOK_SECRET` | Signing secret for the `/stripeWebhook` endpoint. |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON credentials for Android Publisher access. |
| `GOOGLE_PLAY_PACKAGE_NAME` | The Play Store package name of the app. |

After setting the variables, deploy the functions:

```bash
cd functions
npm install
npm run deploy
```

## Running the Flutter app

1. Install dependencies:

   ```bash
   flutter pub get
   ```

2. Run the application as usual:

   ```bash
   flutter run
   ```

3. Optional build-time flags:
   - `--dart-define=PAYMENTS_PROVIDER=stripe|play|auto` (defaults to `auto`)
   - `--dart-define=FUNCTIONS_REGION=your-region` (defaults to `us-central1`)

The store page automatically chooses Google Play Billing when available and
falls back to Stripe Checkout otherwise. Manual coin top-ups always use Stripe
Checkout with a server-enforced daily limit.

## Stripe webhook

Configure your Stripe dashboard to send Checkout and Payment Intent events to:

```
https://<REGION>-<PROJECT_ID>.cloudfunctions.net/stripeWebhook
```

Use the signing secret from the dashboard as `STRIPE_WEBHOOK_SECRET`.

## Google Play verification

The Android client forwards purchase tokens to
`https://<REGION>-<PROJECT_ID>.cloudfunctions.net/verifyPlayPurchase`. The cloud
function validates the purchase with the Android Publisher API, enforces the
daily limit, acknowledges the purchase, and updates the Firestore wallet.

## Profile Edit

The profile editor allows members to update their avatar, cover photo, display
name, unique @username, bio, website, location, and birthday. Images are
uploaded to Firebase Storage at:

- `users/{uid}/profile.jpg` for the avatar
- `users/{uid}/cover.jpg` for the cover image

Profile metadata is stored under `users/{uid}` in Cloud Firestore using the
following shape:

```json
{
  "displayName": "string",
  "username": "lowercase string",
  "bio": "string | null",
  "website": "https://... | null",
  "location": "string | null",
  "birthdate": "Timestamp | null",
  "photoURL": "string | null",
  "coverURL": "string | null",
  "privacy": {
    "showEmail": false,
    "dmPermission": "all" | "followers"
  },
  "updatedAt": "Timestamp"
}
```

> **Note:** The `coins`, `vipTier`, `vipSince`, and `verified` fields are
> server-managed. The client only reads and displays them; updates must flow
> through Cloud Functions or administrative tooling to prevent tampering.

Enable the Firestore security rule that only allows a signed-in user to create
or update their own document:

```text
match /users/{uid} {
  allow read: if isSignedIn() && request.auth.uid == uid;
  allow write: if isSignedIn() && request.auth.uid == uid;
}
```

Grant the authenticated user the Storage permissions required for `users/{uid}`
paths so avatars and covers can be uploaded.
