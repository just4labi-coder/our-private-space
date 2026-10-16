# Orbit Two — Password reset email branding

Firebase Authentication sends password-reset emails using the template configured in the Firebase Console. The Flutter app cannot change the sender name, template design, or add an image to that built-in email by changing Dart code alone.

## Built-in Firebase template (works without custom SMTP)

In Firebase Console, open **Authentication → Templates → Password reset** and set:

- **Sender name:** Orbit Two
- **Subject:** Reset your Orbit Two password
- **Body:**

Hello,

We received a request to reset the password for your Orbit Two account (%EMAIL%).

To choose a new password, open this secure link:

%LINK%

If you did not request a password reset, you can safely ignore this email. Your password will not change unless you open the link and complete the reset.

For your security, do not forward this email or share the reset link with anyone.

— Orbit Two Support

## Logo and large styled link

The built-in Firebase Authentication template does not provide full control over custom HTML branding and an embedded app logo. To guarantee the Orbit Two logo and a large, styled button/link, configure a trusted SMTP sender and use a custom HTML email template through a server-side email service. Do not put SMTP passwords or API keys in the Flutter app or GitHub source.

After saving the template, send a real password-reset test to an account you control and verify the sender name, subject, link, and spam-folder placement.
