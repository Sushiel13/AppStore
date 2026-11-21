package com.appbucket.adshield

/**
 * Minimal IPv4 / UDP / DNS helpers. We only ever see UDP packets to our fake
 * DNS server, so this deliberately ignores everything else.
 */
object DnsPacket {

    class Query(
        val srcIp: ByteArray,
        val dstIp: ByteArray,
        val srcPort: Int,
        val dstPort: Int,
        val dns: ByteArray,
    )

    /** Returns the DNS payload of an IPv4/UDP packet, or null if it is not one. */
    fun parse(packet: ByteArray, length: Int): Query? {
        if (length < 28) return null
        val version = (packet[0].toInt() shr 4) and 0xF
        if (version != 4) return null
        val ihl = (packet[0].toInt() and 0xF) * 4
        if (packet[9].toInt() != 17) return null // not UDP
        if (length < ihl + 8) return null
        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)
        val srcPort = u16(packet, ihl)
        val dstPort = u16(packet, ihl + 2)
        val udpLen = u16(packet, ihl + 4)
        val end = minOf(length, ihl + udpLen)
        if (end <= ihl + 8) return null
        return Query(srcIp, dstIp, srcPort, dstPort, packet.copyOfRange(ihl + 8, end))
    }

    /** Reads the first question name from a DNS message, e.g. "ads.example.com". */
    fun questionName(dns: ByteArray): String? {
        if (dns.size < 12) return null
        val qdCount = u16(dns, 4)
        if (qdCount < 1) return null
        val sb = StringBuilder()
        var i = 12
        while (i < dns.size) {
            val len = dns[i].toInt() and 0xFF
            if (len == 0) return if (sb.isEmpty()) null else sb.toString()
            if ((len and 0xC0) != 0) return null // compression not expected in a query
            if (i + 1 + len > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (j in 1..len) sb.append((dns[i + j].toInt() and 0xFF).toChar())
            i += len + 1
        }
        return null
    }

    /** Builds an NXDOMAIN answer for a blocked query. */
    fun blockedResponse(query: ByteArray): ByteArray {
        val r = query.copyOf()
        // QR=1, keep opcode + RD, RA=1, RCODE=3 (NXDOMAIN)
        r[2] = ((query[2].toInt() and 0x79) or 0x80).toByte()
        r[3] = 0x83.toByte()
        // ANCOUNT, NSCOUNT, ARCOUNT = 0
        for (k in 6..11) r[k] = 0
        // Trim any additional records (e.g. EDNS OPT) after the question.
        val qEnd = questionEnd(query)
        return if (qEnd in 12..r.size) r.copyOf(qEnd) else r
    }

    private fun questionEnd(dns: ByteArray): Int {
        var i = 12
        while (i < dns.size) {
            val len = dns[i].toInt() and 0xFF
            if (len == 0) return i + 1 + 4 // zero byte + QTYPE + QCLASS
            i += len + 1
        }
        return -1
    }

    /** Wraps a DNS reply into an IPv4/UDP packet going back to the app that asked. */
    fun buildReply(q: Query, dns: ByteArray): ByteArray {
        val total = 20 + 8 + dns.size
        val p = ByteArray(total)
        p[0] = 0x45
        put16(p, 2, total)
        p[6] = 0x40 // don't fragment
        p[8] = 64 // TTL
        p[9] = 17 // UDP
        System.arraycopy(q.dstIp, 0, p, 12, 4) // from fake DNS server
        System.arraycopy(q.srcIp, 0, p, 16, 4) // back to the app
        put16(p, 10, ipChecksum(p, 20))
        put16(p, 20, q.dstPort)
        put16(p, 22, q.srcPort)
        put16(p, 24, 8 + dns.size)
        // UDP checksum 0 = not used (allowed for IPv4)
        System.arraycopy(dns, 0, p, 28, dns.size)
        return p
    }

    private fun ipChecksum(p: ByteArray, len: Int): Int {
        var sum = 0
        var i = 0
        while (i < len) {
            sum += u16(p, i)
            i += 2
        }
        while ((sum shr 16) != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv() and 0xFFFF
    }

    private fun u16(b: ByteArray, o: Int) =
        ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)

    private fun put16(b: ByteArray, o: Int, v: Int) {
        b[o] = (v shr 8).toByte()
        b[o + 1] = v.toByte()
    }
}
