package com.appbucket.adshield

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton

/** Get Pro: choose a plan, pay by UPI, send the details on WhatsApp, enter the unlock code. */
class ProActivity : AppCompatActivity() {

    private var plan = Pro.YEARLY

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pro)
        Pro.init(this)

        val planY = findViewById<MaterialButton>(R.id.planY)
        val planM = findViewById<MaterialButton>(R.id.planM)
        val pay = findViewById<MaterialButton>(R.id.payUpi)
        fun choose(p: Pro.Plan) {
            plan = p
            planY.isChecked = p == Pro.YEARLY
            planM.isChecked = p == Pro.MONTHLY
            pay.text = "Pay ₹${p.price} by UPI"
        }
        planY.setOnClickListener { choose(Pro.YEARLY) }
        planM.setOnClickListener { choose(Pro.MONTHLY) }
        choose(Pro.YEARLY)

        val phone = Pro.phoneId(this)
        findViewById<TextView>(R.id.upiId).text = "UPI ID: ${Pro.UPI_ID} · tap to copy"
        findViewById<TextView>(R.id.upiId).setOnClickListener { copy("UPI ID", Pro.UPI_ID) }
        findViewById<TextView>(R.id.phoneId).text = "Your phone ID: $phone · tap to copy"
        findViewById<TextView>(R.id.phoneId).setOnClickListener { copy("Phone ID", phone) }

        pay.setOnClickListener {
            val i = Intent(Intent.ACTION_VIEW, Uri.parse(Pro.upiLink(this, plan)))
            try {
                startActivity(Intent.createChooser(i, "Pay with"))
            } catch (e: Exception) {
                copy("UPI ID", Pro.UPI_ID)
                Toast.makeText(this, "No UPI app found. UPI ID copied: pay ₹${plan.price} to ${Pro.UPI_ID}", Toast.LENGTH_LONG).show()
            }
        }
        findViewById<MaterialButton>(R.id.sendWa).setOnClickListener {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Pro.whatsAppLink(this, plan))))
            } catch (e: Exception) {
                Toast.makeText(this, "WhatsApp not found. Send your phone ID $phone and UPI ref to +91 99607 97128", Toast.LENGTH_LONG).show()
            }
        }

        val code = findViewById<EditText>(R.id.code)
        val err = findViewById<TextView>(R.id.codeErr)
        intent?.data?.getQueryParameter("code")?.let { code.setText(it) }    // adshield://pro?code=...
        findViewById<MaterialButton>(R.id.unlock).setOnClickListener {
            val msg = Pro.apply(this, code.text.toString())
            if (msg != null) {
                err.text = msg
                err.visibility = View.VISIBLE
            } else {
                err.visibility = View.GONE
                val lic = Pro.license(this)!!
                Toast.makeText(this, "Pro unlocked until ${Pro.pretty(lic.expires)}. Thank you!", Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        findViewById<TextView>(R.id.proStatus).text = Pro.statusLine(this).removeSuffix(" · Get Pro").removeSuffix(" · Renew")
    }

    private fun copy(label: String, value: String) {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(label, value))
        Toast.makeText(this, "$label copied", Toast.LENGTH_SHORT).show()
    }
}
