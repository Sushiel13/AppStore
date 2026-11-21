package com.appbucket.adshield

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class MainActivity : AppCompatActivity() {

    private lateinit var toggle: MaterialButton
    private lateinit var status: TextView
    private lateinit var queries: TextView
    private lateinit var blocked: TextView
    private lateinit var listSize: TextView
    private lateinit var adapter: ArrayAdapter<String>
    private lateinit var emptyLog: TextView

    private val handler = Handler(Looper.getMainLooper())
    private val refresher = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 1000)
        }
    }

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) BlockerVpnService.start(this)
            else Toast.makeText(this, "VPN permission is needed to block ads", Toast.LENGTH_LONG).show()
        }

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        toggle = findViewById(R.id.toggle)
        status = findViewById(R.id.status)
        queries = findViewById(R.id.statQueries)
        blocked = findViewById(R.id.statBlocked)
        listSize = findViewById(R.id.statList)
        emptyLog = findViewById(R.id.emptyLog)

        adapter = ArrayAdapter(this, R.layout.item_log, R.id.logText, mutableListOf())
        val logList = findViewById<ListView>(R.id.logList)
        logList.adapter = adapter
        logList.setOnItemClickListener { _, _, pos, _ ->
            val domain = adapter.getItem(pos)?.substringAfter("  ")?.trim() ?: return@setOnItemClickListener
            confirmAllow(domain)
        }

        toggle.setOnClickListener { if (Stats.running) BlockerVpnService.stop(this) else requestStart() }
        findViewById<MaterialButton>(R.id.updateList).setOnClickListener { updateBlocklist() }
        findViewById<MaterialButton>(R.id.allowlist).setOnClickListener { showAllowlist() }
        findViewById<MaterialButton>(R.id.resetStats).setOnClickListener { Stats.reset(); render() }

        Thread { Blocklist.load(applicationContext); runOnUiThread { render() } }.start()

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onResume() {
        super.onResume()
        handler.post(refresher)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(refresher)
    }

    private fun requestStart() {
        val intent = VpnService.prepare(this)
        if (intent != null) vpnPermission.launch(intent) else BlockerVpnService.start(this)
    }

    private fun render() {
        val on = Stats.running
        toggle.text = if (on) "ON" else "OFF"
        val color = ContextCompat.getColor(this, if (on) R.color.shield_on else R.color.shield_off)
        toggle.backgroundTintList = ColorStateList.valueOf(color)
        status.text = if (on) "Protected — ads & trackers are being blocked"
        else "Not protected — tap to start blocking"
        queries.text = Stats.queries.get().toString()
        blocked.text = Stats.blocked.get().toString()
        listSize.text = "%,d".format(Blocklist.size)

        val items = Stats.recentBlocked()
        adapter.clear()
        adapter.addAll(items)
        emptyLog.visibility = if (items.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun updateBlocklist() {
        Toast.makeText(this, "Downloading full blocklist…", Toast.LENGTH_SHORT).show()
        Thread {
            val msg = try {
                val n = Blocklist.downloadRemote(applicationContext)
                "Blocklist updated: %,d domains".format(n)
            } catch (e: Exception) {
                "Update failed: ${e.message}"
            }
            runOnUiThread {
                Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
                render()
            }
        }.start()
    }

    private fun confirmAllow(domain: String) {
        MaterialAlertDialogBuilder(this)
            .setTitle("Allow $domain?")
            .setMessage("Use this if a website or app is broken. This domain will no longer be blocked.")
            .setPositiveButton("Allow") { _, _ ->
                Blocklist.allow(this, domain)
                Toast.makeText(this, "$domain allowed", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showAllowlist() {
        val items = Blocklist.allowedDomains()
        if (items.isEmpty()) {
            MaterialAlertDialogBuilder(this)
                .setTitle("Allowlist")
                .setMessage("Nothing allowed yet. Tap a blocked domain in the list to allow it.")
                .setPositiveButton("OK", null)
                .show()
            return
        }
        MaterialAlertDialogBuilder(this)
            .setTitle("Allowlist — tap to remove")
            .setItems(items.toTypedArray()) { _, which ->
                Blocklist.disallow(this, items[which])
                Toast.makeText(this, "${items[which]} will be blocked again", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Close", null)
            .show()
    }
}
