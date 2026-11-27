package com.appbucket.jarvis

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarvis/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setAlarm" -> {
                        val i = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_HOUR, call.argument<Int>("hour")!!)
                            putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minute")!!)
                            call.argument<String>("label")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) }
                            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                        }
                        start(i)
                        result.success(true)
                    }
                    "setTimer" -> {
                        val i = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                            putExtra(AlarmClock.EXTRA_LENGTH, call.argument<Int>("seconds")!!)
                            call.argument<String>("label")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) }
                            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                        }
                        start(i)
                        result.success(true)
                    }
                    "showAlarms" -> {
                        start(Intent(AlarmClock.ACTION_SHOW_ALARMS))
                        result.success(true)
                    }
                    "torch" -> {
                        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val id = cm.cameraIdList.firstOrNull {
                            cm.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                        } ?: throw Exception("this phone has no flashlight")
                        cm.setTorchMode(id, call.argument<Boolean>("on") == true)
                        result.success(true)
                    }
                    "battery" -> {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        result.success(
                            mapOf(
                                "level" to bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                                "charging" to bm.isCharging,
                            )
                        )
                    }
                    "apps" -> {
                        val pm = packageManager
                        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        @Suppress("DEPRECATION")
                        val list = pm.queryIntentActivities(i, 0)
                            .filter { it.activityInfo.packageName != packageName }
                            .map { mapOf("name" to it.loadLabel(pm).toString(), "package" to it.activityInfo.packageName) }
                            .distinctBy { it["package"] }
                        result.success(list)
                    }
                    "launch" -> {
                        val pkg = call.argument<String>("package")!!
                        val i = packageManager.getLaunchIntentForPackage(pkg) ?: throw Exception("can't open $pkg")
                        start(i)
                        result.success(true)
                    }
                    "open" -> {
                        val uri = Uri.parse(call.argument<String>("uri")!!)
                        val pkg = call.argument<String>("package")
                        if (pkg != null) {
                            try {
                                start(Intent(Intent.ACTION_VIEW, uri).setPackage(pkg))
                                result.success(true)
                                return@setMethodCallHandler
                            } catch (e: Exception) {
                                // app not installed: fall back to any app that can open it
                            }
                        }
                        start(Intent(Intent.ACTION_VIEW, uri))
                        result.success(true)
                    }
                    "dial" -> {
                        start(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + call.argument<String>("number")!!)))
                        result.success(true)
                    }
                    "sms" -> {
                        val i = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + call.argument<String>("number")!!))
                        call.argument<String>("body")?.let { if (it.isNotEmpty()) i.putExtra("sms_body", it) }
                        start(i)
                        result.success(true)
                    }
                    "action" -> {
                        start(Intent(call.argument<String>("action")!!))
                        result.success(true)
                    }
                    "volume" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val dir = when (call.argument<String>("direction")) {
                            "up" -> AudioManager.ADJUST_RAISE
                            "down" -> AudioManager.ADJUST_LOWER
                            "mute" -> AudioManager.ADJUST_MUTE
                            else -> AudioManager.ADJUST_UNMUTE
                        }
                        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun start(i: Intent) {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
    }
}
