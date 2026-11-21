package com.appbucket.adshield

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Holds the set of blocked domains and the user's allowlist.
 * Sources: a small bundled list (assets/blocklist.txt) plus an optional
 * downloaded hosts file (StevenBlack unified hosts) saved in app storage.
 */
object Blocklist {

    const val REMOTE_URL = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    private const val DOWNLOADED_FILE = "hosts_downloaded.txt"
    private const val PREFS = "adshield"
    private const val KEY_ALLOW = "allowlist"

    @Volatile private var blocked: Set<String> = emptySet()
    @Volatile private var allowed: Set<String> = emptySet()

    val size: Int get() = blocked.size

    fun load(context: Context) {
        val set = HashSet<String>(200_000)
        context.assets.open("blocklist.txt").bufferedReader().useLines { lines ->
            lines.forEach { parseLine(it)?.let(set::add) }
        }
        val downloaded = File(context.filesDir, DOWNLOADED_FILE)
        if (downloaded.exists()) {
            downloaded.bufferedReader().useLines { lines ->
                lines.forEach { parseLine(it)?.let(set::add) }
            }
        }
        blocked = set
        allowed = prefs(context).getStringSet(KEY_ALLOW, emptySet())!!.toSet()
    }

    /** Downloads the big hosts list. Runs on a background thread. Returns domain count. */
    fun downloadRemote(context: Context): Int {
        val conn = URL(REMOTE_URL).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        try {
            if (conn.responseCode != 200) throw IllegalStateException("HTTP ${conn.responseCode}")
            val tmp = File(context.filesDir, "$DOWNLOADED_FILE.tmp")
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
            tmp.renameTo(File(context.filesDir, DOWNLOADED_FILE))
        } finally {
            conn.disconnect()
        }
        load(context)
        return blocked.size
    }

    /** Accepts plain "domain" lines or hosts-file lines like "0.0.0.0 domain". */
    private fun parseLine(raw: String): String? {
        val line = raw.substringBefore('#').trim()
        if (line.isEmpty()) return null
        val parts = line.split(Regex("\\s+"))
        val domain = (if (parts.size >= 2) parts[1] else parts[0]).lowercase().trimEnd('.')
        if (domain.isEmpty() || !domain.contains('.')) return null
        if (domain == "localhost" || domain == "0.0.0.0" || domain.endsWith(".localdomain")) return null
        return domain
    }

    /** True if the domain or any parent domain is on the list and not allowlisted. */
    fun isBlocked(domain: String): Boolean {
        var d = domain.lowercase().trimEnd('.')
        if (isAllowed(d)) return false
        while (true) {
            if (blocked.contains(d)) return true
            val dot = d.indexOf('.')
            if (dot < 0 || dot == d.length - 1) return false
            d = d.substring(dot + 1)
            if (!d.contains('.')) return false
        }
    }

    private fun isAllowed(domain: String): Boolean {
        var d = domain
        while (true) {
            if (allowed.contains(d)) return true
            val dot = d.indexOf('.')
            if (dot < 0) return false
            d = d.substring(dot + 1)
        }
    }

    fun allowedDomains(): List<String> = allowed.sorted()

    fun allow(context: Context, domain: String) {
        allowed = allowed + domain.lowercase()
        prefs(context).edit().putStringSet(KEY_ALLOW, allowed).apply()
    }

    fun disallow(context: Context, domain: String) {
        allowed = allowed - domain.lowercase()
        prefs(context).edit().putStringSet(KEY_ALLOW, allowed).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
