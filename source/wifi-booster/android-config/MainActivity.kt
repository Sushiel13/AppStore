package com.appbucket.wifibooster

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

class MainActivity : FlutterActivity() {

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wifibooster/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasLocation" -> result.success(hasLocation())
                    "locationOn" -> result.success(locationOn())
                    "requestLocation" -> {
                        if (hasLocation()) {
                            result.success(true)
                        } else {
                            pendingPermission?.success(false)
                            pendingPermission = result
                            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 7)
                        }
                    }
                    "wifiInfo" -> result.success(wifiInfo())
                    "scan" -> scan(result)
                    "openSettings" -> {
                        val action = call.argument<String>("action") ?: Settings.ACTION_WIFI_SETTINGS
                        if (!start(Intent(action))) start(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    "openWifiPanel" -> {
                        val ok = if (Build.VERSION.SDK_INT >= 29) start(Intent(Settings.Panel.ACTION_WIFI)) else false
                        if (!ok) start(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    "openUrl" -> {
                        start(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!)))
                        result.success(true)
                    }
                    "appSettings" -> {
                        start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message ?: e.toString(), null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7) {
            pendingPermission?.success(hasLocation())
            pendingPermission = null
        }
    }

    private fun hasLocation(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun locationOn(): Boolean {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun wifiManager() = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    @Suppress("DEPRECATION")
    private fun wifiInfo(): Map<String, Any?> {
        val wm = wifiManager()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var onWifi = false
        var lp: LinkProperties? = null
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                onWifi = true
                lp = cm.getLinkProperties(n)
                break
            }
        }
        val out = HashMap<String, Any?>()
        out["wifiEnabled"] = wm.isWifiEnabled
        out["connected"] = onWifi
        if (!onWifi) return out

        val info = wm.connectionInfo
        var ssid = info.ssid ?: ""
        if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length >= 2) ssid = ssid.substring(1, ssid.length - 1)
        if (ssid == "<unknown ssid>") ssid = ""
        out["ssid"] = ssid
        val bssid = info.bssid
        out["bssid"] = if (bssid == null || bssid == "02:00:00:00:00:00") "" else bssid
        out["rssi"] = info.rssi
        out["linkSpeed"] = info.linkSpeed
        out["frequency"] = info.frequency
        if (Build.VERSION.SDK_INT >= 29) {
            out["txSpeed"] = info.txLinkSpeedMbps
            out["rxSpeed"] = info.rxLinkSpeedMbps
        }
        if (Build.VERSION.SDK_INT >= 30) {
            out["standard"] = info.wifiStandard
            out["maxTx"] = info.maxSupportedTxLinkSpeedMbps
        }

        var gateway = ""
        var ip = ""
        val dns = ArrayList<String>()
        if (lp != null) {
            for (r in lp.routes) {
                val g = r.gateway
                if (r.isDefaultRoute && g is Inet4Address) { gateway = g.hostAddress ?: ""; break }
            }
            for (a in lp.linkAddresses) {
                if (a.address is Inet4Address) { ip = a.address.hostAddress ?: ""; break }
            }
            for (d in lp.dnsServers) dns.add(d.hostAddress ?: "")
            if (Build.VERSION.SDK_INT >= 28) {
                out["privateDns"] = lp.isPrivateDnsActive
                out["privateDnsName"] = lp.privateDnsServerName ?: ""
            }
        }
        if (gateway.isEmpty()) {
            val g = wm.dhcpInfo?.gateway ?: 0
            if (g != 0) gateway = "${g and 0xff}.${g shr 8 and 0xff}.${g shr 16 and 0xff}.${g shr 24 and 0xff}"
        }
        out["gateway"] = gateway
        out["ip"] = ip
        out["dns"] = dns
        return out
    }

    @Suppress("DEPRECATION")
    private fun scan(result: MethodChannel.Result) {
        if (!hasLocation()) {
            result.error("permission", "Location permission is needed to see nearby networks", null)
            return
        }
        val wm = wifiManager()
        var done = false
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver

        fun finish() {
            if (done) return
            done = true
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            val list = ArrayList<Map<String, Any?>>()
            for (s in wm.scanResults) {
                val m = HashMap<String, Any?>()
                m["ssid"] = s.SSID ?: ""
                m["bssid"] = s.BSSID ?: ""
                m["level"] = s.level
                m["frequency"] = s.frequency
                m["width"] = when (s.channelWidth) {
                    1 -> 40
                    2 -> 80
                    3 -> 160
                    4 -> 80
                    5 -> 320
                    else -> 20
                }
                list.add(m)
            }
            result.success(list)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) { finish() }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, filter)
        // Android limits how often apps can scan; if it refuses, the last results are used.
        val started = try { wm.startScan() } catch (_: Exception) { false }
        handler.postDelayed({ finish() }, if (started) 6000L else 300L)
    }

    private fun start(i: Intent): Boolean {
        return try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }
}
