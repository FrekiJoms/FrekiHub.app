package com.frekihub.freki_hub

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import java.util.Calendar

/** Persistent, single-occurrence alarms. Repeating schedules use the next local day. */
object RuleNotifications {
    private const val CHANNEL = "frekihub_rule_reminders"
    private fun prefs(c: Context) = c.getSharedPreferences("rule_notifications", Context.MODE_PRIVATE)
    fun exactAllowed(c: Context) = Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    fun count(c: Context) = prefs(c).all.values.count {
        val s = JSONObject(it as String)
        s.optInt("limit") == -1 || s.optInt("sent") < s.optInt("limit")
    }
    private fun operation(c: Context, key: String, due: Long, token: String) = PendingIntent.getBroadcast(c, 0,
        Intent(c, RuleNotificationReceiver::class.java).setData(Uri.Builder().scheme("frekihub").authority("reminder").appendPath(key).build())
            .putExtra("key", key).putExtra("due", due).putExtra("token", token),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun nextTime(time: String, after: Long): Long {
        val parts = time.split(":")
        val date = Calendar.getInstance().apply {
            timeInMillis = after
            set(Calendar.HOUR_OF_DAY, parts[0].toInt()); set(Calendar.MINUTE, parts[1].toInt())
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= after) {
                add(Calendar.DAY_OF_YEAR, 1)
                // Restore the requested clock time after a DST gap normalized today's value.
                set(Calendar.HOUR_OF_DAY, parts[0].toInt()); set(Calendar.MINUTE, parts[1].toInt())
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
        }
        return date.timeInMillis
    }

    private fun arm(c: Context, key: String, state: JSONObject) {
        if (state.getInt("limit") != -1 && state.getInt("sent") >= state.getInt("limit")) return
        val alarm = c.getSystemService(AlarmManager::class.java)
        val intent = operation(c, key, state.getLong("due"), state.getString("token"))
        if (exactAllowed(c)) {
            try { alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, state.getLong("due"), intent); return }
            catch (_: SecurityException) { /* Access may be revoked between checking and scheduling. */ }
        }
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, state.getLong("due"), intent)
    }

    @Synchronized fun sync(c: Context, restore: Boolean = false) {
        val storage = prefs(c)
        val wanted = mutableSetOf<String>()
        val rules = Automation.config(c).optJSONArray("rules")
        if (rules != null) for (r in 0 until rules.length()) {
            val rule = rules.getJSONObject(r)
            if (!rule.optBoolean("enabled", true)) continue
            val schedules = rule.optJSONObject("program")?.optJSONArray("schedules") ?: continue
            for (n in 0 until minOf(schedules.length(), 16)) {
                val definition = schedules.getJSONObject(n)
                val key = rule.getString("id") + ":" + definition.getString("name")
                wanted.add(key)
                // Source changes also restart the delivery counter; context refreshes never do.
                val fingerprint = rule.optString("source") + definition.toString()
                val old = storage.getString(key, null)?.let { JSONObject(it) }
                val state = if (old?.optString("fingerprint") == fingerprint) JSONObject(old.toString()) else JSONObject()
                    .put("fingerprint", fingerprint).put("token", java.util.UUID.randomUUID().toString())
                    .put("definition", definition).put("limit", definition.getInt("count")).put("sent", 0)
                    .put("due", nextTime(definition.getString("time"), System.currentTimeMillis()))
                val modeChanged = !state.has("exact") || state.optBoolean("exact") != exactAllowed(c)
                state.put("exact", exactAllowed(c))
                if (restore) state.put("due", nextTime(definition.getString("time"), System.currentTimeMillis()))
                if (old == null || old.toString() != state.toString()) storage.edit().putString(key, state.toString()).commit()
                if (restore || modeChanged || old == null || old.optString("fingerprint") != fingerprint) arm(c, key, state)
            }
        }
        for (key in storage.all.keys - wanted) {
            val state = JSONObject(storage.getString(key, "{}")!!)
            val intent = operation(c, key, state.optLong("due"), state.optString("token"))
            c.getSystemService(AlarmManager::class.java).cancel(intent)
            intent.cancel()
            storage.edit().remove(key).commit()
        }
    }

    @Synchronized fun deliver(c: Context, intent: Intent) {
        // Check the current enabled rules even if configuration changed as the alarm arrived.
        sync(c)
        val key = intent.getStringExtra("key") ?: return
        val storage = prefs(c)
        val state = storage.getString(key, null)?.let { JSONObject(it) } ?: return
        val due = state.getLong("due")
        if (due != intent.getLongExtra("due", -1) || state.getString("token") != intent.getStringExtra("token") || System.currentTimeMillis() < due) return
        if (state.getInt("limit") != -1 && state.getInt("sent") >= state.getInt("limit")) return
        val definition = state.getJSONObject("definition")
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Rule reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val allowed = (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
        var delivered = false
        if (allowed) {
            val open = PendingIntent.getActivity(c, 93, Intent(c, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
            val notification = builder.setSmallIcon(R.drawable.ic_transaction)
                .setContentTitle(definition.getString("title")).setContentText(definition.getString("body"))
                .setStyle(Notification.BigTextStyle().bigText(definition.getString("body")))
                .setContentIntent(open).setAutoCancel(true).setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE).build()
            try { manager.notify("rule:$key:$due", 93, notification); delivered = true }
            catch (_: SecurityException) { }
        }
        if (delivered) {
            state.put("sent", state.getInt("sent") + 1)
            Automation.emit(c, JSONObject().put("action", "scheduled_notification").put("time", System.currentTimeMillis())
                .put("title", "Sent reminder: " + definition.getString("title")).put("schedule", definition.getString("name")))
        }
        // Skip missed occurrences instead of sending a burst. Denied permission consumes no repeat count.
        if (definition.getBoolean("daily") || !delivered) {
            state.put("due", nextTime(definition.getString("time"), maxOf(System.currentTimeMillis(), due)))
        }
        storage.edit().putString(key, state.toString()).commit()
        if (definition.getBoolean("daily") || !delivered) arm(c, key, state)
    }
}

class RuleNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { RuleNotifications.deliver(context, intent) }
}
