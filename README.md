# AdShield — Ad & Tracker Blocker (local VPN)

An Android app that blocks ads, trackers and analytics across **all apps and browsers**, on Wi-Fi and mobile data. It uses Android's VPN feature locally, so **no VPN server is needed** and your normal traffic is not routed anywhere.

## How it works
- The app starts a local VPN that only captures **DNS lookups** (sent to a fake DNS address, 10.111.222.2).
- Each lookup is checked against the blocklist:
  - **Blocked** → the app answers "domain does not exist", so the ad never loads.
  - **Allowed** → the lookup is forwarded to Cloudflare (1.1.1.1), falling back to Google (8.8.8.8).
- All other traffic goes out directly, so speed and battery use are barely affected.

## Features
- One-tap ON/OFF shield with a persistent notification (with a Stop button)
- Live counters: blocked requests, DNS lookups, domains in the list
- Recently blocked log. Tap a domain to **allowlist** it if a site or app breaks.
- **Update list** downloads the StevenBlack unified hosts list (~150k domains). A starter list is bundled.
- Android 7.0+ (minSdk 24), built for Android 14 (targetSdk 34)

## Build (GitHub Actions)
Every push to `main` runs `.github/workflows/build-apk.yml`:
1. Installs JDK 17, the Android SDK and Gradle 8.9
2. Builds the APK
3. Uploads it as a workflow artifact **and** publishes a GitHub Release `v1.0.<run>` with the APK attached. That release is your download link.

You can also run it by hand from **Actions → Build AdShield APK → Run workflow**.

## Limitations
- **Private DNS** (Settings → Network → Private DNS) set to a specific hostname bypasses blocking. Set it to *Off* or *Automatic*.
- Chrome's **Use secure DNS** can bypass it too. Turn that off in Chrome settings for full blocking.
- Ads served from the same domain as the content (YouTube video ads, Instagram sponsored posts) can't be blocked by DNS. This is true for every DNS blocker.
- Only one VPN can be active at a time on Android.
- IPv4 DNS only.

## Project layout
```
app/src/main/java/com/appbucket/adshield/
  MainActivity.kt        UI: toggle, stats, log, allowlist
  BlockerVpnService.kt   VpnService: TUN reader, blocking, upstream forwarding
  DnsPacket.kt           IPv4/UDP/DNS parsing and reply building
  Blocklist.kt           Bundled + downloaded lists, allowlist
  Stats.kt               Counters and recent-blocked log
app/src/main/assets/blocklist.txt   starter blocklist
```

## Play Store note
Google Play restricts ad blockers that interfere with other apps' ads. Distribute it as an APK (for example on AppBucket) or through F-Droid.
