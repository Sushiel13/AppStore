package com.appbucket.adshield

import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedList
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

/** In-memory counters and a short log of recently blocked domains, read by the UI. */
object Stats {
    val queries = AtomicLong(0)
    val blocked = AtomicLong(0)
    @Volatile var running = false

    private const val MAX_LOG = 100
    private val log = LinkedList<String>()
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    fun recordBlocked(domain: String) {
        blocked.incrementAndGet()
        synchronized(log) {
            log.addFirst("${fmt.format(Date())}  $domain")
            if (log.size > MAX_LOG) log.removeLast()
        }
    }

    fun recentBlocked(): List<String> = synchronized(log) { log.toList() }

    fun reset() {
        queries.set(0)
        blocked.set(0)
        synchronized(log) { log.clear() }
    }
}
