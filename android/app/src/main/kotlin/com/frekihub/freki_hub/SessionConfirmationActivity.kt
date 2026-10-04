package com.frekihub.freki_hub

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import org.json.JSONObject

/** A notification-launched host for the native cross-app confirmation.
 * No Flutter engine or database is opened; SQLite is updated on reconciliation.
 */
class SessionConfirmationActivity : Activity() {
    private var dialog: AlertDialog? = null
    private var draft: EditText? = null
    private var restoredNote: String? = null
    private var awaitingPermission = false
    private var destroying = false
    private val prefs get() = getSharedPreferences("session", MODE_PRIVATE)
    private val sessionId get() = intent.getStringExtra("sessionId")

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        awaitingPermission = state?.getBoolean("awaitingPermission") ?: false
        restoredNote = state?.getString("draft")
    }

    override fun onResume() {
        super.onResume()
        if (sessionId == null || sessionId != prefs.getString("id", null)) { finish(); return }
        if (dialog != null) return
        if (Settings.canDrawOverlays(this)) {
            awaitingPermission = false
            showConfirmation()
        } else if (awaitingPermission) {
            // Back/denial never counts as acceptance and never ends the session.
            finish()
        } else {
            showConfirmation(permissionHint = true)
        }
    }

    private fun showConfirmation(permissionHint: Boolean = false) {
        val snapshot = try { JSONObject(Automation.prefs(this).getString("snapshot", "{}")!!) } catch (_: Exception) { JSONObject() }
        val theme = snapshot.optString("settings.theme", "system")
        val dark = theme == "dark" || (theme != "light" && resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
        val foreground = Color.parseColor(if (dark) "#EDF0E8" else "#20231F")
        val muted = Color.parseColor(if (dark) "#BBC2B6" else "#626B61")
        val surface = Color.parseColor(if (dark) "#20251F" else "#F7F8F4")
        fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
        val metrics = windowManager.currentWindowMetrics
        val insets = metrics.windowInsets.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.systemBars())
        val available = metrics.bounds.height() - insets.top - insets.bottom
        val horizontalActions = available < dp(600) && metrics.bounds.width() > dp(360)
        fun background(color: Int, radius: Int = 24) = GradientDrawable().apply { setColor(color); cornerRadius = dp(radius).toFloat() }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(20))
            background = background(surface, 28)
        }
        fun text(value: String, size: Float, bold: Boolean = false) = TextView(this).apply {
            text = value; textSize = size; setTextColor(if (bold) foreground else muted)
            if (bold) setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 0, 0, dp(12))
        }
        root.addView(text(if (permissionHint) "Confirm wherever you are" else "End this session?", 24f, true))
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        if (permissionHint) {
            body.addView(text("A final check, without leaving your current app.", 16f))
            body.addView(text("Review before ending", 16f, true))
            body.addView(text("Clock out opens a confirmation and an editable session note over the app you are using.", 14f))
            body.addView(text("You stay in control", 16f, true))
            body.addView(text("It appears only when you tap Clock out. Your timer keeps running until you confirm.", 14f))
            body.addView(text("On the next screen, enable Display over other apps for FrekiHub.", 12f))
        } else {
            body.addView(text("Review your note before ending. Your timer is still running.", 14f))
            val started = prefs.getLong("started", System.currentTimeMillis())
            body.addView(Chronometer(this).apply {
                base = SystemClock.elapsedRealtime() - maxOf(0L, System.currentTimeMillis() - started)
                textSize = 28f; setTextColor(foreground); typeface = Typeface.MONOSPACE
                setPadding(0, dp(4), 0, dp(16)); start()
        })
        body.addView(text("Session note", 14f, true))
        val storedNote = prefs.getString("note", "") ?: ""
        val initial = if (snapshot.optString("_runningId") == sessionId) snapshot.optString("session.note", storedNote) else storedNote
        draft = EditText(this).apply {
            setText(restoredNote ?: initial); hint = "What did you work on?"
            setTextColor(foreground); setHintTextColor(muted)
            textSize = 16f; minLines = 2; maxLines = 4; gravity = Gravity.TOP
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = background(Color.parseColor(if (dark) "#30372D" else "#EAEEE5"), 16)
            contentDescription = "Session note"
        }
        body.addView(draft)
        }
        root.addView(ScrollView(this).apply { addView(body); isFillViewport = false }, LinearLayout.LayoutParams(-1, 0, 1f))
        fun button(label: String, primary: Boolean, action: () -> Unit) = Button(this).apply {
            text = label; isAllCaps = false; textSize = 16f; minHeight = dp(48)
            setTextColor(if (primary) surface else foreground)
            background = background(if (primary) foreground else Color.TRANSPARENT, 24)
            setOnClickListener { action() }
        }
        val actions = LinearLayout(this).apply { orientation = if (horizontalActions) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL }
        actions.addView(button(if (permissionHint) "Allow overlay" else "End session", true) {
            if (permissionHint) {
                awaitingPermission = true
                dialog?.dismiss(); dialog = null
                try {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                } catch (_: Exception) { finish() }
            } else {
                if (SessionService.confirmEnd(this, sessionId!!, draft!!.text.toString())) {
                    dialog?.dismiss()
                } else {
                    Toast.makeText(this, "Session changed or could not be ended. Your action was not saved.", Toast.LENGTH_LONG).show()
                    if (sessionId != prefs.getString("id", null)) dialog?.dismiss()
                }
            }
        }, LinearLayout.LayoutParams(if (horizontalActions) 0 else -1, -2, if (horizontalActions) 1f else 0f))
        actions.addView(button("Keep running", false) { dialog?.dismiss() }, LinearLayout.LayoutParams(if (horizontalActions) 0 else -1, -2, if (horizontalActions) 1f else 0f).apply {
            if (horizontalActions) marginStart = dp(8) else topMargin = dp(8)
        })
        root.addView(actions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        root.isFocusableInTouchMode = true
        root.requestFocus()
        val nativeDialog = AlertDialog.Builder(this).setView(root).create()
        dialog = nativeDialog
        nativeDialog.setOnDismissListener { if (!destroying && !awaitingPermission) finish() }
        nativeDialog.window?.apply {
            if (!permissionHint) setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            setBackgroundDrawableResource(android.R.color.transparent)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            attributes = attributes.apply { dimAmount = .24f }
        }
        try {
            nativeDialog.show()
            nativeDialog.window?.setLayout(minOf(dp(420), metrics.bounds.width() - dp(32)), minOf(dp(if (permissionHint) 440 else 480), (available * .70).toInt()))
        } catch (_: Exception) {
            Toast.makeText(this, "Overlay access is unavailable. Your session is still running.", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    override fun onSaveInstanceState(state: Bundle) {
        state.putBoolean("awaitingPermission", awaitingPermission)
        state.putString("draft", draft?.text?.toString() ?: restoredNote)
        super.onSaveInstanceState(state)
    }

    override fun onDestroy() {
        destroying = true
        dialog?.dismiss(); dialog = null
        super.onDestroy()
    }
}
