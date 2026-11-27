# Jarvis

A light voice assistant for everyday phone tasks. Flutter app, Android only.

Speak or type: alarms, timers, reminders, calls, WhatsApp and SMS, opening apps, torch, volume, Wi-Fi/Bluetooth switches, battery, weather (Open-Meteo, no key), notes, lists (shopping, to-do…), maths, YouTube, maps and web search.

Optional "smart answers": the person can add their own Google Gemini key, or any OpenAI-compatible server (Groq, OpenRouter, or Ollama/OpenJarvis on their own computer) in Settings.

Everything is stored on the phone. There is no server.

## Build

Pushing changes under `source/jarvis/` runs `.github/workflows/jarvis.yml`, which:

1. creates the Android project with `flutter create` and patches it with `tool/setup_android.py` (app id, permissions, our `android-config/MainActivity.kt`, icons),
2. runs `flutter analyze` and the unit tests in `test/`,
3. builds the release APK and commits it to `apps/jarvis/Jarvis.apk` for appbucket.in,
4. saves the build logs to the `ci-log-jarvis` branch.

The APK is signed with `android-config/test-signing.jks` unless a `JARVIS_KEYSTORE_B64` secret is set (password `jarvis-store`, alias `jarvis`). Keep using the same key, or installed copies can't update.

## Files

- `lib/brain.dart` – understands requests and carries them out
- `lib/parse.dart` – times, durations and sums (unit tested)
- `lib/native.dart` + `android-config/MainActivity.kt` – alarms, torch, apps, volume, settings screens
- `lib/phone.dart` – reminders (notifications) and contacts
- `lib/online.dart` – weather and optional AI
- `lib/main.dart`, `lib/settings.dart` – screens
