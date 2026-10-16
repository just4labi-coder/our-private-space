# Orbit Two notification Worker

This Worker is designed for Orbit Two's Firebase project `our-privet-space`. It sends FCM HTTP v1 push notifications for newly saved chat messages and can send a branded HTML email only when the receiving user's Firestore profile has `emailNotifications: true`.

## Required Cloudflare settings

1. Create a Worker named `orbit-two-notifications` and deploy this folder.
2. Add Worker secrets:
   - `FIREBASE_WEB_API_KEY`: the Firebase Web API key for the app.
   - `FIREBASE_SERVICE_ACCOUNT_JSON`: the complete private service-account JSON for project `our-privet-space`. Never commit this JSON or paste it into chat.
3. Enable the Cloudflare Email Service, onboard and verify a sender domain, then set the `EMAIL_FROM` Worker variable to a sender address on that verified domain. The `EMAIL` binding is declared in `wrangler.toml`.
4. Configure the GitHub Actions repository variable `ORBIT_WORKER_URL` with the deployed Worker URL, for example `https://orbit-two-notifications.<your-subdomain>.workers.dev`.
5. The service account must have only the permissions needed to read Firestore and send Firebase Cloud Messaging for this project. Do not use a personal account's key.

## Endpoint

- `GET /health` reports that the Worker is reachable.
- `POST /notify-message` requires `Authorization: Bearer <Firebase ID token>` and JSON `{"spaceId":"...","messageId":"..." }`. The Worker verifies the Firebase token, active space membership, and the stored message's sender before sending notifications. It never accepts a recipient UID or FCM token from the app.

## Email behavior

Email notifications are opt-in. The receiver's `users/{uid}` profile must contain `emailNotifications: true`; by default the app must leave this setting off. Email sending also requires a verified sender domain and an enabled Cloudflare Email Service binding. The free email quota is separate from the Workers request quota and can vary by account.

## Security notes

- Do not put service-account JSON, private keys, SMTP passwords, or email API keys in GitHub.
- Keep Firebase Firestore rules enabled. The Worker uses server credentials only on the server side.
- This endpoint currently handles new chat messages. Edits, unsends, deletions, and shared-data change events need separate event handling.
