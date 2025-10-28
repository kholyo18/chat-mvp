# Chat MVP

This repository contains the Flutter client and Firebase resources for the chat
MVP application. The app now ships with server-verified coin purchases through
Google Play Billing and Stripe Checkout.

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
