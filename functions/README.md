# Cloud Functions for Payments

This package hosts the Firebase Cloud Functions that power Stripe Checkout and
Google Play Billing verification for the chat MVP application.

## Local development

```bash
cd functions
npm install
firebase emulators:start --only functions
```

The functions expect the following environment variables:

| Variable | Description |
| --- | --- |
| `STRIPE_SECRET_KEY` | Stripe secret key for creating Checkout sessions. |
| `STRIPE_WEBHOOK_SECRET` | Signing secret for the Stripe webhook endpoint. |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON credentials for a Play Console service account with Android Publisher access. |
| `GOOGLE_PLAY_PACKAGE_NAME` | The application package name used for Google Play purchases. |

When running locally you can export these variables or use
`firebase functions:config:set` and emulate with
`firebase emulators:start --only functions`.

## Deployment

```bash
cd functions
npm install
npm run deploy
```

Ensure Firestore security rules and indexes are deployed as well so that the
server side verification succeeds.
