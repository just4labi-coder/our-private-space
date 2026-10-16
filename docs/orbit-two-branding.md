# Orbit Two branding assets

## App launcher icon

Replace `assets/branding/orbit_two_logo.jpg` with your own square app logo, keeping the exact filename and path. Use a high-resolution square image (at least 512 × 512 pixels). Keep important artwork near the centre so Android's circular, rounded-square, and themed launchers do not crop it.

The APK workflow now uses the committed image directly and no longer overwrites it from the old base64 backup. After replacing the image, run the **Build APK** workflow. It regenerates the launcher icon from `pubspec.yaml`.

## Optional Android monochrome themed icon

To support Android themed icons, add a transparent PNG containing only the monochrome logo at:

`assets/branding/orbit_two_logo_monochrome.png`

Keep the filename exact. The workflow uses `flutter_launcher_icons_monochrome.yaml` when this file exists. Use a simple single-colour foreground with transparent background for best results.

## Password-reset email logo

The email HTML loads its logo from the `ORBIT_LOGO_URL` Firebase Functions secret. The URL must be a publicly accessible direct HTTPS image URL. The app icon file in the GitHub repository is not automatically a public web URL, so after choosing the logo, upload a copy to a trusted HTTPS image host and set that direct URL as the secret. Never put SMTP credentials in this file or in GitHub.
