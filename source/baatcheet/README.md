# BaatCheet

A WeChat-style chat app for Android: 1-to-1 and group chats (text, photos, voice messages, read receipts, recall), contacts with friend requests and QR codes, a Moments feed with likes and comments, and 1-to-1 voice and video calls.

It runs on Firebase's free **Spark** plan: Firebase Authentication (email + password) and Cloud Firestore. Photos and voice notes are compressed and stored inside Firestore, so Cloud Storage (which now needs the paid plan) isn't used.

## How it's built

`.github/workflows/baatcheet.yml` builds the APK on every push that touches `source/baatcheet/` and saves it to `apps/baatcheet/BaatCheet.apk`. The Android project is generated in CI by `flutter create`, then patched by `tool/setup_android.py`. `tool/gen_firebase_options.py` reads `android-config/google-services.json`.

## One-time Firebase setup

1. Go to https://console.firebase.google.com and **Create a project** named `BaatCheet` (Google Analytics can be off).
2. **Build → Authentication → Get started → Email/Password → Enable → Save.**
3. **Build → Firestore Database → Create database →** location `asia-south1 (Mumbai)` **→ Start in production mode.**
4. In Firestore, open the **Rules** tab, replace everything with the contents of `firestore.rules`, and **Publish**.
5. **Project settings (gear) → Your apps → Android icon.** Package name: `in.appbucket.baatcheet`. Register, then **download `google-services.json`**.
6. Put that file at `source/baatcheet/android-config/google-services.json` (replace the placeholder) and push. The next build connects to your project.

## Signing key

Builds use the test key in `android-config/test-signing.jks` until the repository secret `BAATCHEET_KEYSTORE_B64` is set (Settings → Secrets and variables → Actions → New repository secret). Set it before the first public release: phones can only update an app signed with the same key. Keep a private copy of the release keystore; if it's lost, users must uninstall to get updates.

## Limits of the free setup

- No server push: new-message and incoming-call alerts arrive while the app is open or still running in the background. Adding Firebase Cloud Messaging with a Cloud Function (paid Blaze plan) would make them arrive when the app is closed.
- Calls use public STUN servers only. On some mobile networks (strict NAT) a call can fail to connect; adding a TURN server fixes that.
- Group calls aren't included; calls are 1-to-1.
- Each photo is capped at about 650 KB and voice messages at 60 seconds.
