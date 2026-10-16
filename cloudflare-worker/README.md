# Orbit Two push notification Worker

This Worker sends Firebase Cloud Messaging (FCM HTTP v1) push notifications for newly saved chat messages in Firebase project `our-privet-space`. **Email is intentionally paused** and is not part of this setup.

## Required Cloudflare settings

1. Create a Worker named `orbit-two-notifications` and deploy the `cloudflare-worker` folder.
2. Add these Worker secrets:
   - `FIREBASE_WEB_API_KEY`: a Firebase API key that permits Identity Toolkit requests. If the existing key is restricted to Android apps, create a separate server-side key that permits the Identity Toolkit API; do not use Android-only application restrictions for this key.
   - `FIREBASE_SERVICE_ACCOUNT_JSON`: the complete private service-account JSON for project `our-privet-space`. Never commit this JSON or paste it into chat.
3. Configure the GitHub Actions repository variable `ORBIT_WORKER_URL` with the deployed Worker URL, such as `https://orbit-two-notifications.<your-subdomain>.workers.dev`. Cloudflare provides a free `workers.dev` address; a custom domain is not needed for push notifications.
4. Give the service account only the permissions needed to read Firestore and send Firebase Cloud Messaging for this project. Do not use a personal account's key.

## Endpoints

- `GET /health` reports that the Worker is reachable.
- `POST /notify-message` requires `Authorization: Bearer <Firebase ID token>` and JSON `{"spaceId":"...","messageId":"..."}`. The Worker verifies the Firebase token, active space membership, and stored message sender before sending. The app cannot choose a recipient UID or FCM token.

## Current scope

- Sends push notifications for newly saved chat messages.
- Uses each recipient device's `hideNotificationDetails` preference.
- Email sending and its Settings toggle are paused for now; we can add them after push notifications are verified.
- This Worker must be deployed and its secrets configured before push notifications can reach the partner's phone.
- Firestore/FCM credentials must stay in Cloudflare Worker secrets, never in GitHub source code.

## Troubleshooting

- Check `GET /health` first.
- Verify the deployed Worker URL is saved as the GitHub Actions repository variable `ORBIT_WORKER_URL`, then rebuild the APK.
- Confirm both devices are signed in, have notification permission enabled, and have registered an FCM token under `users/{uid}/pushTokens`.
- Check Cloudflare Worker logs if the app reports that the notification request failed.
