# Orbit Two branding assets

## Main app icon

Replace `assets/branding/orbit_two_logo.jpg` with the final square Orbit Two logo. Keep the exact filename so the APK workflow and launcher-icon configuration can find it. Use a clear, centered logo with safe padding because Android launcher masks crop the corners. A 1024 × 1024 image is recommended.

The build workflow also reads `assets/branding/orbit_two_logo.jpg.base64` to restore the JPG during the GitHub Actions build. If you replace the JPG, update the Base64 file from the same image as well, otherwise the workflow may restore the old logo.

## Android themed / monochrome icon

For Android launchers that support themed icons, add a transparent PNG named:

`assets/branding/orbit_two_logo_monochrome.png`

Use only the logo symbol in a single solid color with a transparent background. Do not include a colored square or text that becomes unreadable when the launcher recolors it. Keep the same 1024 × 1024 canvas and centered safe area.

The configuration is in `flutter_launcher_icons_monochrome.yaml`. When the monochrome PNG exists, the GitHub Actions workflow generates the themed launcher icon automatically.

## Email logo

Firebase Authentication's built-in password-reset template does not provide full control over a branded HTML layout or embedded app logo. The logo assets above only control the app icon. A branded reset email needs a trusted email service/SMTP integration and a hosted HTTPS logo URL (or a supported inline image). Keep SMTP passwords and API keys in secret storage, never in source files or GitHub commits.
