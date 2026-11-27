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


s = sub(r'applicationId = "[^"]*"', 'applicationId = "com.appbucket.jarvis"', s, "applicationId")
s = sub(r"minSdk = [^\n]+", "minSdk = 24", s, "minSdk")
s = sub(r"ndkVersion = [^\n]+", 'ndkVersion = "27.0.12077973"', s, "ndkVersion")
s = sub(r"compileOptions \{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, "compileOptions")
s = sub(
    r"\n    buildTypes \{",
    """
    signingConfigs {
        create("release") {
            val ks = System.getenv("JV_KEYSTORE")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("JV_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("JV_KEY_ALIAS")
                keyPassword = System.getenv("JV_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {""",
    s,
    "signingConfigs",
)
s = sub(
    r'signingConfig = signingConfigs\.getByName\("debug"\)',
    'signingConfig = signingConfigs.getByName(if (System.getenv("JV_KEYSTORE") != null) "release" else "debug")\n'
    '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
    s,
    "release signingConfig",
)
s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
s = sub(r"compileSdk = [^\n]+", "compileSdk = 36", s, "compileSdk")
gradle.write_text(s)

(app / "proguard-rules.pro").write_text(
    "-keep class com.dexterous.** { *; }\n"
    "-keepattributes Signature\n"
    "-keepattributes *Annotation*\n"
    "-keep class com.google.gson.reflect.TypeToken { *; }\n"
    "-keep class * extends com.google.gson.reflect.TypeToken\n"
)

settings = root / "android" / "settings.gradle.kts"
t = settings.read_text()
t = sub(r'id\("org\.jetbrains\.kotlin\.android"\) version "[^"]*"', 'id("org.jetbrains.kotlin.android") version "2.1.0"', t, "kotlin version")
settings.write_text(t)

# Our MainActivity with the native helpers (alarms, torch, apps, volume…)
kt = list((app / "src" / "main" / "kotlin").rglob("MainActivity.kt"))
if not kt:
    raise SystemExit("setup_android: MainActivity.kt not found")
shutil.copy(root / "android-config" / "MainActivity.kt", kt[0])

manifest = app / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.READ_CONTACTS",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.VIBRATE",
    "android.permission.WAKE_LOCK",
    "android.permission.USE_EXACT_ALARM",
    "com.android.alarm.permission.SET_ALARM",
]
lines = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms)
lines += '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>\n'
lines += '    <uses-feature android:name="android.hardware.camera.flash" android:required="false"/>\n'
lines += '    <uses-feature android:name="android.hardware.microphone" android:required="false"/>\n'
m = m.replace("<application", lines + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Jarvis"', m, count=1)
# Allow plain http so people can point the AI at Ollama/OpenJarvis on their own computer.
m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>"""
m = m.replace("</application>", receivers.lstrip("\n"), 1)

queries = """
        <intent><action android:name="android.speech.RecognitionService"/></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
        <intent>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent><action android:name="android.intent.action.DIAL"/></intent>
        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="smsto"/></intent>
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
