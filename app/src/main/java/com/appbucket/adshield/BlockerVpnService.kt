package com.appbucket.adshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Local "DNS-only" VPN. Only traffic to a fake DNS server (10.111.222.2) is routed
 * into the tunnel, so normal browsing is untouched and no remote server is needed.
 * Each DNS query is checked against the blocklist: blocked -> NXDOMAIN,
 * otherwise forwarded to a real upstream resolver and the answer passed back.
 */
class BlockerVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.appbucket.adshield.START"
        const val ACTION_STOP = "com.appbucket.adshield.STOP"
        private const val TAG = "AdShield"
        private const val CHANNEL_ID = "adshield_vpn"
        private const val NOTIF_ID = 1
        private const val VPN_ADDRESS = "10.111.222.1"
        private const val FAKE_DNS = "10.111.222.2"
        private val UPSTREAMS = listOf("1.1.1.1", "8.8.8.8")

        fun start(ctx: Context) {
            val i = Intent(ctx, BlockerVpnService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, BlockerVpnService::class.java).setAction(ACTION_STOP))
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var readerThread: Thread? = null
    private var workers: ExecutorService? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdown()
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground()
        if (tun == null) startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        try {
            if (Blocklist.size == 0) Blocklist.load(this)
            val builder = Builder()
                .setSession(getString(R.string.app_name))
                .addAddress(VPN_ADDRESS, 32)
                .addDnsServer(FAKE_DNS)
                .addRoute(FAKE_DNS, 32)
                .setBlocking(true)
            if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
            val pfd = builder.establish() ?: run {
                Log.w(TAG, "VPN permission missing")
                stopSelf()
                return
            }
            tun = pfd
            workers = Executors.newFixedThreadPool(8)
            Stats.running = true
            readerThread = Thread({ readLoop(pfd) }, "adshield-tun").also { it.start() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN", e)
            shutdown()
            stopSelf()
        }
    }

    private fun readLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val buf = ByteArray(32767)
        try {
            while (!Thread.currentThread().isInterrupted) {
                val n = input.read(buf)
                if (n <= 0) continue
                val q = DnsPacket.parse(buf, n) ?: continue
                if (q.dstPort != 53) continue
                workers?.execute { handleQuery(q, output) }
            }
        } catch (e: Exception) {
            Log.i(TAG, "TUN reader stopped: ${e.message}")
        }
    }

    private fun handleQuery(q: DnsPacket.Query, output: FileOutputStream) {
        Stats.queries.incrementAndGet()
        val name = DnsPacket.questionName(q.dns)
        val reply: ByteArray? = if (name != null && Blocklist.isBlocked(name)) {
            Stats.recordBlocked(name)
            DnsPacket.blockedResponse(q.dns)
        } else {
            forward(q.dns)
        }
        if (reply != null) {
            val packet = DnsPacket.buildReply(q, reply)
            try {
                synchronized(output) { output.write(packet) }
            } catch (e: Exception) {
                Log.w(TAG, "Write to TUN failed: ${e.message}")
            }
        }
    }

    private fun forward(dns: ByteArray): ByteArray? {
        for (server in UPSTREAMS) {
            try {
                DatagramSocket().use { s ->
                    protect(s) // keep upstream traffic outside our own tunnel
                    s.soTimeout = 4000
                    s.send(DatagramPacket(dns, dns.size, InetAddress.getByName(server), 53))
                    val resp = ByteArray(4096)
                    val p = DatagramPacket(resp, resp.size)
                    s.receive(p)
                    return resp.copyOf(p.length)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Upstream $server failed: ${e.message}")
            }
        }
        return null
    }

    private fun startInForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Ad blocking", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), piFlags)
        val stop = PendingIntent.getService(
            this, 1, Intent(this, BlockerVpnService::class.java).setAction(ACTION_STOP), piFlags
        )
        val n: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_shield)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Blocking ads & trackers")
            .setContentIntent(open)
            .addAction(0, "Stop", stop)
            .setOngoing(true)
            .build()
        ServiceCompat.startForeground(
            this, NOTIF_ID, n,
            if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        )
    }

    private fun shutdown() {
        Stats.running = false
        readerThread?.interrupt()
        readerThread = null
        try { tun?.close() } catch (_: Exception) {}
        tun = null
        workers?.shutdownNow()
        workers = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    override fun onRevoke() {
        shutdown()
        stopSelf()
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }
}
