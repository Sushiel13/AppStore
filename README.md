# AppBucket

My own Android app store website. It lists my apps with screenshots, details, reviews and a direct APK download. It's hosted free on GitHub Pages at appbucket.in, with a small free Cloudflare Worker for download counts, visitor counts and messages.

## What's in it

- `index.html` – the whole store (home, search, categories, app pages, My apps, help, publish tool)
- `apps.json` – store name, categories and every app's details. **This is the only file you edit to change the store.**
- `apps/<app-id>/` – each app's icon (512×512 PNG), screenshots, APK and privacy policy
- `vendor/qrcode.js` – QR code library (MIT licence)
- `manifest.webmanifest`, `sw.js`, `store-icon*` – lets people add the store to their home screen
- `CNAME`, `.nojekyll` – serve the repo as-is on GitHub Pages at appbucket.in
- `worker/` – the API (download counter, visitor counter, forms) for Cloudflare Workers; `.github/workflows/worker.yml` deploys it
- `owner/` – owner-only page: Pro unlock codes, and the messages people send
- `tests/` – tests for the API (`npm test`)

## Add or update an app

1. Open the store's **Publish an app** page (footer link), fill in the form and copy the result.
2. Paste it into the `apps` list in `apps.json`.
3. Put the files in `apps/<app-id>/`: `icon.png`, the `.apk`, `privacy.html` and `shots/`.
4. For an update, replace the APK, raise `version` and `versionCode`, set `updated`, and add a `changelog` entry at the top. People who downloaded the old version will see **Update** in My apps.
5. Push to GitHub. GitHub Pages publishes it in a minute or two, and the API redeploys so the new app's downloads are counted.

## Download counts, visitors and messages

These run on a free Cloudflare Worker (`worker/`), because GitHub Pages only serves files. The site finds it through `"api"` in `apps.json` (for example `"https://appbucket-api.yourname.workers.dev"`). If `api` is empty, the store still works but hides the counts and can't send messages.

- Every tap on **Install** is counted. The same person downloading the same app more than once on the same day counts once.
- Each browser is counted once as a visitor.
- See the exact totals any time at `<api>/api/downloads` and `<api>/api/visitors`.
- Totals from the old Netlify counter (8 downloads, 297 visitors on 19 Nov 2026) are carried over through `START_DOWNLOADS` and `START_VISITORS` in `worker/wrangler.toml`.
- Had downloads from elsewhere? Put that number in the app's `baseDownloads` in `apps.json`; it's added to the live count.

Reviews, problem reports and update sign-ups are saved by the Worker. Read and delete them on the owner page (`/owner/`) with your owner key. To show a review on the site, add it to that app's `reviews` list in `apps.json`:

```json
{ "name": "Priya", "rating": 5, "date": "2026-11-05", "text": "Very useful for my cook's salary.", "reply": "Thank you, Priya!" }
```

### One-time Cloudflare setup

1. Make a free account at dash.cloudflare.com and pick a workers.dev subdomain (Workers & Pages).
2. Create an API token with the **Edit Cloudflare Workers** template. Copy your **Account ID** from the dashboard.
3. In GitHub → this repo → Settings → Secrets and variables → Actions, add `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and `OWNER_KEY` (any long password you choose).
4. Run **Actions → Deploy API (Cloudflare Worker) → Run workflow**. Put the Worker address it prints into `"api"` in `apps.json`.

## Run locally

```
python3 -m http.server 8000
```
Then open http://localhost:8000.
