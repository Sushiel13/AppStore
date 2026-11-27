package com.appbucket.adshield

import android.content.Context
import android.content.SharedPreferences
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * AdShield Pro: a 14-day free trial from the first time this version runs, then blocking needs Pro.
 * Pro is bought by UPI and unlocked with a code signed by the owner for this phone's ID (see License).
 *
 * The app remembers the latest date it has seen, so turning the phone's clock back doesn't
 * extend the trial or a Pro code.
 */
object Pro {
    const val TRIAL_DAYS = 14
    const val UPI_ID = "9960797128@kotak"
    const val PAYEE = "AppBucket"
    const val WHATSAPP = "919960797128"

    data class Plan(val key: String, val name: String, val price: Int, val days: Int, val per: String)

    val MONTHLY = Plan("M", "Monthly", 29, 31, "month")
    val YEARLY = Plan("Y", "Yearly", 249, 366, "year")
    val PLANS = listOf(YEARLY, MONTHLY)

    private const val PREFS = "adshield_pro"
    private val ymd = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    private fun prefs(ctx: Context): SharedPreferences = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Sets up the phone ID and trial on first run, and moves the "latest date seen" forward. */
    fun init(ctx: Context) {
        val p = prefs(ctx)
        val e = p.edit()
        if (p.getString("dev", null) == null) e.putString("dev", newPhoneId())
        val now = ymd.format(Calendar.getInstance().time)
        if (p.getString("trial", null) == null) e.putString("trial", now)
        if ((p.getString("seen", "") ?: "") < now) e.putString("seen", now)
        e.apply()
    }

    private fun newPhoneId(): String {
        val a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        val r = SecureRandom()
        val c = (1..8).map { a[r.nextInt(a.length)] }.joinToString("")
        return "ADS-${c.substring(0, 4)}-${c.substring(4)}"
    }

    fun phoneId(ctx: Context): String {
        init(ctx)
        return prefs(ctx).getString("dev", "")!!
    }

    /** Today, but never earlier than the latest date the app has seen. */
    fun today(ctx: Context): String {
        init(ctx)
        val seen = prefs(ctx).getString("seen", "")!!
        val now = ymd.format(Calendar.getInstance().time)
        return if (now > seen) now else seen
    }

    private fun addDays(date: String, days: Int): String {
        val c = Calendar.getInstance()
        c.time = ymd.parse(date)!!
        c.add(Calendar.DAY_OF_MONTH, days)
        return ymd.format(c.time)
    }

    private fun daysBetween(from: String, to: String): Int {
        val a = ymd.parse(from)!!.time
        val b = ymd.parse(to)!!.time
        return Math.round((b - a) / 86_400_000.0).toInt()
    }

    fun trialEnds(ctx: Context): String = addDays(prefs(ctx).getString("trial", today(ctx))!!, TRIAL_DAYS)

    fun trialDaysLeft(ctx: Context): Int = maxOf(0, daysBetween(today(ctx), trialEnds(ctx)))

    /** The stored licence if it is genuine for this phone and not over yet. */
    fun license(ctx: Context): License.Result? {
        val code = prefs(ctx).getString("lic", null) ?: return null
        val r = License.verify(code, phoneId(ctx)) ?: return null
        return if (r.expires >= today(ctx)) r else null
    }

    fun isActive(ctx: Context): Boolean = trialDaysLeft(ctx) > 0 || license(ctx) != null

    /** Checks a code and saves it. Returns an error message, or null if Pro is now unlocked. */
    fun apply(ctx: Context, code: String): String? {
        val r = License.verify(code, phoneId(ctx))
            ?: return "This code isn't right for this phone. Check you copied all of it, and that it was made for ${phoneId(ctx)}."
        if (r.expires < today(ctx)) return "This code ended on ${pretty(r.expires)}. Ask for a new one."
        val cur = license(ctx)
        if (cur != null && cur.expires > r.expires) return "You already have Pro until ${pretty(cur.expires)}, longer than this code."
        prefs(ctx).edit().putString("lic", r.code).apply()
        return null
    }

    fun planName(key: String) = if (key == "Y") YEARLY.name else MONTHLY.name

    fun pretty(date: String): String =
        SimpleDateFormat("d MMM yyyy", Locale.ENGLISH).format(ymd.parse(date)!!)

    /** One line for the main screen. */
    fun statusLine(ctx: Context): String {
        val lic = license(ctx)
        if (lic != null) {
            val left = daysBetween(today(ctx), lic.expires)
            return if (left <= 7) "Pro (${planName(lic.plan)}) ends ${pretty(lic.expires)} · Renew"
            else "Pro (${planName(lic.plan)}) · until ${pretty(lic.expires)}"
        }
        val t = trialDaysLeft(ctx)
        return if (t > 0) "Free trial · $t ${if (t == 1) "day" else "days"} left · Get Pro"
        else "Free trial ended · Get Pro to keep blocking ads"
    }

    fun upiLink(ctx: Context, plan: Plan): String {
        val note = java.net.URLEncoder.encode("AdShield Pro ${plan.name} ${phoneId(ctx)}", "UTF-8").replace("+", "%20")
        return "upi://pay?pa=$UPI_ID&pn=$PAYEE&am=${plan.price}.00&cu=INR&tn=$note"
    }

    fun whatsAppLink(ctx: Context, plan: Plan): String {
        val text = "AdShield Pro\nPlan: ${plan.name} (₹${plan.price})\nPhone ID: ${phoneId(ctx)}\nI have paid by UPI. UPI ref no: "
        return "https://wa.me/$WHATSAPP?text=" + java.net.URLEncoder.encode(text, "UTF-8").replace("+", "%20")
    }
}
