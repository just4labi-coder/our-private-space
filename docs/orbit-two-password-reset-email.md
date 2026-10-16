# Orbit Two — branded password-reset email setup

The app's **Forgot Password?** action now calls the server-side Firebase callable function `sendBrandedPasswordResetEmail`. The function generates a Firebase password-reset link and sends it through the configured SMTP provider. The SMTP credentials stay in Firebase Functions secrets, never in the Flutter app or GitHub source.

## 1. Set up the sender

Choose an SMTP provider and verify the sender address/domain with that provider. Use the provider's SMTP host, port, username, and password. Do not use your normal email account password unless the provider explicitly instructs you to use an app password.

## 2. Add Firebase Functions secrets

From the repository root, run these commands in a trusted terminal. Each command prompts for the value, so do not put secret values in a command line, source file, screenshot, or GitHub commit.

```bash
firebase functions:secrets:set SMTP_HOST
firebase functions:secrets:set SMTP_PORT
firebase functions:secrets:set SMTP_USER
firebase functions:secrets:set SMTP_PASS
firebase functions:secrets:set SMTP_FROM
firebase functions:secrets:set ORBIT_LOGO_URL
```

Use port `465` for implicit TLS or `587` for STARTTLS, according to the SMTP provider. `SMTP_FROM` must be a sender address/name accepted by the provider, for example `Orbit Two <verified-sender@example.com>`. Replace that example with your own verified sender.

`ORBIT_LOGO_URL` must be a publicly reachable HTTPS image URL. After adding your own app logo to a trusted public host, use its direct image URL. Do not use a private Drive link that requires signing in. If the URL is empty, the email falls back to a simple heart mark.

## 3. Deploy the server function

Install the Firebase CLI and sign in, select the correct Firebase project, then run from the repository root:

```bash
firebase use YOUR_FIREBASE_PROJECT_ID
firebase deploy --only functions:sendBrandedPasswordResetEmail
```

Replace `YOUR_FIREBASE_PROJECT_ID` with the actual Firebase project ID. This callable function uses the secrets listed above. Firebase may require the Blaze billing plan for deployment and runtime use.

For push notifications, deploy the notification functions too:

```bash
firebase deploy --only functions
```

Review the project selection before deploying. The functions must be deployed to the same Firebase project used by the Android app.

## 4. Firebase Authentication template

The app's Forgot Password action uses the branded SMTP function instead of Firebase's built-in email sender. The built-in **Authentication → Templates → Password reset** template therefore does not control emails sent by this custom function. You may still set a clear sender name and subject there for other Firebase flows, but it will not replace the custom HTML email.

## 5. Test

After deployment, open the app, choose **Forgot Password?**, and enter an account email you control. Verify the sender name, subject, Orbit Two logo, large reset button, text link, and inbox/spam placement. Also verify that the reset link opens the Firebase password-reset page.

Never add SMTP passwords or secret values to GitHub, the Flutter app, or a public issue. If a secret is accidentally exposed, rotate it with the SMTP provider and update the Firebase Functions secret.
