"""Patches the Android project that `flutter create` generated."""
import pathlib
import re
import shutil

root = pathlib.Path(__file__).resolve().parent.parent
app = root / "android" / "app"
gradle = app / "build.gradle.kts"
s = gradle.read_text()


def sub(pattern, repl, text, what):
    new, n = re.subn(pattern, repl, text, count=1)
    if n == 0:
        raise SystemExit(f"setup_android: could not patch {what}")
    return new


s = sub(r'applicationId = "[^"]*"', 'applicationId = "com.appbucket.wifibooster"', s, "applicationId")
s = sub(r"minSdk = [^\n]+", "minSdk = 24", s, "minSdk")
s = sub(r"ndkVersion = [^\n]+", 'ndkVersion = "27.0.12077973"', s, "ndkVersion")
s = sub(
    r"\n    buildTypes \{",
    """
    signingConfigs {
        create("release") {
            val ks = System.getenv("WB_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("WB_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WB_KEY_ALIAS")
                keyPassword = System.getenv("WB_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {""",
    s,
    "signingConfigs",
)
s = sub(
    r'signingConfig = signingConfigs\.getByName\("debug"\)',
    'signingConfig = signingConfigs.getByName(if (System.getenv("WB_KEYSTORE") != null) "release" else "debug")',
    s,
    "release signingConfig",
)
s = sub(r"compileSdk = [^\n]+", "compileSdk = 36", s, "compileSdk")
gradle.write_text(s)

settings = root / "android" / "settings.gradle.kts"
t = settings.read_text()
t = sub(r'id\("org\.jetbrains\.kotlin\.android"\) version "[^"]*"', 'id("org.jetbrains.kotlin.android") version "2.1.0"', t, "kotlin version")
settings.write_text(t)

# Our MainActivity with the Wi-Fi helpers (connection info, nearby scan, settings shortcuts)
kt = list((app / "src" / "main" / "kotlin").rglob("MainActivity.kt"))
if not kt:
    raise SystemExit("setup_android: MainActivity.kt not found")
shutil.copy(root / "android-config" / "MainActivity.kt", kt[0])

manifest = app / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]
lines = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms)
lines += '    <uses-feature android:name="android.hardware.wifi" android:required="false"/>\n'
m = m.replace("<application", lines + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="WiFi Booster"', m, count=1)
# Router admin pages are plain http (http://192.168.1.1).
m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

queries = """
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="http"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
"""
if "<queries>" in m:
    m = m.replace("<queries>", "<queries>" + queries, 1)
else:
    m = m.replace("</manifest>", "    <queries>" + queries + "    </queries>\n</manifest>", 1)
manifest.write_text(m)

for d in ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]:
    shutil.copy(root / "assets" / "icon" / f"ic_launcher-{d}.png", app / "src" / "main" / "res" / f"mipmap-{d}" / "ic_launcher.png")

print("Android project patched")
print(m)
