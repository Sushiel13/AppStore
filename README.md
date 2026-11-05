# AppBucket

My own Android app store website. It lists my apps with screenshots, details, reviews and a direct APK download, and it's hosted on Netlify.

## What's in it

- `index.html` – the whole store (home, search, categories, app pages, My apps, help, publish tool)
- `apps.json` – store name, categories and every app's details. **This is the only file you edit to change the store.**
- `apps/<app-id>/` – each app's icon (512×512 PNG), screenshots, APK and privacy policy
- `vendor/qrcode.js` – QR code library (MIT licence)
- `manifest.webmanifest`, `sw.js`, `store-icon*` – lets people add the store to their home screen
- `_headers` – makes APK files download correctly on Netlify
- `netlify/functions/` – the download counter; `netlify.toml` tells Netlify where it is
- `tests/` – tests for the counter (`npm test`)

## Add or update an app

1. Open the store's **Publish an app** page (footer link), fill in the form and copy the result.
2. Paste it into the `apps` list in `apps.json`.
3. Put the files in `apps/<app-id>/`: `icon.png`, the `.apk`, `privacy.html` and `shots/`.
4. For an update, replace the APK, raise `version` and `versionCode`, set `updated`, and add a `changelog` entry at the top. People who downloaded the old version will see **Update** in My apps.
5. Push to GitHub (Netlify redeploys automatically if connected) or drag the folder onto Netlify.

## Download counts

Every tap on **Install** is counted by a small Netlify Function (`netlify/functions/downloads.mjs`) and stored in Netlify Blobs. The store shows the exact total everywhere (e.g. "2 downloads", "1,250 downloads"), including **App info → Total downloads**.

- The same person downloading the same app more than once on the same day counts once.
- See the exact totals any time at `https://<your-site>/api/downloads`.
- Had downloads before the counter existed? Put that number in the app's `baseDownloads` in `apps.json`; it's added to the live count.
- This needs the site deployed from this GitHub repo on Netlify (drag-and-drop deploys don't run functions). Without it, the store still works but hides the download count.

## Reviews and other messages

Reviews, problem reports and update sign-ups arrive in **Netlify → Forms**. To show a review on the site, add it to that app's `reviews` list in `apps.json`:

```json
{ "name": "Priya", "rating": 5, "date": "2026-11-05", "text": "Very useful for my cook's salary.", "reply": "Thank you, Priya!" }
```

## Run locally

```
python3 -m http.server 8000
```
Then open http://localhost:8000.
