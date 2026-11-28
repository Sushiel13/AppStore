# WiFi Speed Booster

Finds what is slowing your Wi-Fi and tells you how to fix it. Flutter app, Android only.

- **Boost** – one tap checks signal, band (2.4 vs 5 GHz), channel crowding, delay to the router and real internet speed, then shows a Wi-Fi score and a boost plan (biggest fix first) with buttons to the right setting or the router page.
- **Speed** – real download / upload / ping / jitter test against Cloudflare's public speed test (speed.cloudflare.com), compared with the user's plan, with history.
- **Signal** – live signal (% and dBm) updated every second to find the best spot, plus band, channel, link speed, Wi-Fi type, IP, router and DNS.
- **Nearby** – nearby networks, a 2.4 GHz channel crowding chart and the quietest channel to set on the router (2.4 and 5 GHz).

It does not pretend to "boost" anything by itself. No app can make the radio faster; the fixes it suggests are the ones that really work.

No account, no server, no ads. History is stored on the phone.

## Build

Pushing changes under `source/wifi-booster/` runs `.github/workflows/wifi-booster.yml`, which:

1. creates the Android project with `flutter create` and patches it with `tool/setup_android.py` (app id `com.appbucket.wifibooster`, permissions, our `android-config/MainActivity.kt`, icons),
2. runs `flutter analyze` and the unit tests in `test/`,
3. builds the release APK and commits it to `apps/wifi-speed-booster/WiFiSpeedBooster.apk` for appbucket.in,
4. saves the build logs to the `ci-log-wifi-booster` branch.

The APK is signed with the keystore in the `WIFIBOOSTER_KEYSTORE_B64` repository secret (base64 of the .jks, password `wifibooster-store`, alias `wifibooster`). Without the secret the build uses a throwaway key and warns. Keep using the same key, or installed copies can't update.

## Files

- `lib/analysis.dart` – channels, signal grades, congestion, best channel and the fix list (unit tested)
- `lib/speedtest.dart` – speed test and router delay
- `lib/native.dart` + `android-config/MainActivity.kt` – Wi-Fi info, nearby scan, location permission, settings shortcuts
- `lib/store.dart` – history and plan speed
- `lib/main.dart` – screens
