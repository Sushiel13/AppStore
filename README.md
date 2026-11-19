# AppBucket

My own Android app store website. It lists my apps with screenshots, details, reviews and a direct APK download. It's hosted free on GitHub Pages at appbucket.in. It's plain files with no server.

## What's in it

- `index.html` – the whole store (home, search, categories, app pages, My apps, help, publish tool)
- `apps.json` – store name, categories and every app's details. **This is the only file you edit to change the store.**
- `apps/<app-id>/` – each app's icon (512×512 PNG), screenshots, APK and privacy policy
- `vendor/qrcode.js` – QR code library (MIT licence)
- `manifest.webmanifest`, `sw.js`, `store-icon*` – lets people add the store to their home screen
- `CNAME`, `.nojekyll` – serve the repo as-is on GitHub Pages at appbucket.in
- `owner/` – owner-only page for making Pro unlock codes

## Add or update an app

1. Open the store's **Publish an app** page (footer link), fill in the form and copy the result.
2. Paste it into the `apps` list in `apps.json`.
3. Put the files in `apps/<app-id>/`: `icon.png`, the `.apk`, `privacy.html` and `shots/`.
4. For an update, replace the APK, raise `version` and `versionCode`, set `updated`, and add a `changelog` entry at the top. People who downloaded the old version will see **Update** in My apps.
5. Push to GitHub. GitHub Pages publishes it in a minute or two.

## Reviews and other messages

The site has no server, so reviews, problem reports and update sign-ups open the visitor's email app with a message to the store email in `apps.json`, already filled in. To show a review on the site, add it to that app's `reviews` list in `apps.json`:

```json
{ "name": "Priya", "rating": 5, "date": "2026-11-05", "text": "Very useful for my cook's salary.", "reply": "Thank you, Priya!" }
```

Download counts and a visitor count aren't shown, because counting needs a server.

## Run locally

```
python3 -m http.server 8000
```
Then open http://localhost:8000.
