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


s = sub(r'applicationId = "[^"]*"', 'applicationId = "in.appbucket.baatcheet"', s, "applicationId")
s = sub(r"minSdk = [^\n]+", "minSdk = 24", s, "minSdk")
s = sub(r"ndkVersion = [^\n]+", 'ndkVersion = "27.0.12077973"', s, "ndkVersion")
s = sub(r"compileOptions \{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, "compileOptions")
s = sub(
    r"\n    buildTypes \{",
    """
    signingConfigs {
        create("release") {
            val ks = System.getenv("BC_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("BC_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("BC_KEY_ALIAS")
                keyPassword = System.getenv("BC_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {""",
    s,
    "signingConfigs",
)
s = sub(
    r'signingConfig = signingConfigs\.getByName\("debug"\)',
    'signingConfig = signingConfigs.getByName(if (System.getenv("BC_KEYSTORE") != null) "release" else "debug")\n'
    '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
    s,
    "release signingConfig",
)
s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
s = sub(r"compileSdk = [^\n]+", "compileSdk = 36", s, "compileSdk")
gradle.write_text(s)

settings = root / "android" / "settings.gradle.kts"
t = settings.read_text()
t = sub(r'id\("org\.jetbrains\.kotlin\.android"\) version "[^"]*"', 'id("org.jetbrains.kotlin.android") version "2.1.0"', t, "kotlin version")
settings.write_text(t)

(app / "proguard-rules.pro").write_text(
    "-keep class org.webrtc.** { *; }\n"
    "-keep class com.cloudwebrtc.webrtc.** { *; }\n"
    "-dontwarn org.webrtc.**\n"
)

manifest = app / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.USE_FULL_SCREEN_INTENT",
    "android.permission.WAKE_LOCK",
    "android.permission.VIBRATE",
]
lines = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms)
lines += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
m = m.replace("<application", lines + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="BaatCheet"', m, count=1)
manifest.write_text(m)

for d in ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]:
    shutil.copy(root / "assets" / "icon" / f"ic_launcher-{d}.png", app / "src" / "main" / "res" / f"mipmap-{d}" / "ic_launcher.png")

print("Android project patched")
