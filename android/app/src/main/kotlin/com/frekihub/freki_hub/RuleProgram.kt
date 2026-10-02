package com.frekihub.freki_hub

import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.os.BatteryManager
import android.location.Location
import org.json.JSONObject
import java.util.Calendar

/** Interprets bounded data from the rule compiler; never executes source code. */
object RuleProgram {
    fun evaluate(node: JSONObject, inside: Boolean?, active: Boolean, now: Calendar, values: JSONObject, depth: Int = 0): Boolean {
        if (depth > 16) return false
        fun child(key: String) = evaluate(node.getJSONObject(key), inside, active, now, values, depth + 1)
        return when (node.optString("op")) {
            "literal" -> node.optBoolean("value")
            "compare" -> {
                val actual = values.opt(node.optString("field")); val expected = node.opt("value")
                if (actual == null || actual == JSONObject.NULL) false else when (node.optString("operator")) {
                    "==" -> if (actual is Number && expected is Number) actual.toDouble() == expected.toDouble() else actual == expected
                    "!=" -> if (actual is Number && expected is Number) actual.toDouble() != expected.toDouble() else actual != expected
                    else -> if (actual !is Number || expected !is Number) false else when (node.optString("operator")) {
                        ">" -> actual.toDouble() > expected.toDouble(); "<" -> actual.toDouble() < expected.toDouble()
                        ">=" -> actual.toDouble() >= expected.toDouble(); "<=" -> actual.toDouble() <= expected.toDouble(); else -> false
                    }
                }
            }
            "inside" -> inside == true
            "outside" -> inside == false
            "active" -> active == node.optBoolean("value", true)
            "not" -> !child("value")
            "and" -> child("left") && child("right")
            "or" -> child("left") || child("right")
            "weekday" -> {
                val day = (now.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                val days = node.getJSONArray("days")
                (0 until days.length()).any { days.optInt(it) == day }
            }
            "time" -> {
                val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val from = node.getInt("from"); val until = node.getInt("until")
                if (from !in 0..1439 || until !in 0..1439 || from == until) false
                else if (from < until) minute >= from && minute < until
                else minute >= from || minute < until
            }
            else -> false
        }
    }

    fun refresh(c: Context) {
        val rules = Automation.config(c).optJSONArray("rules") ?: return
        val last = JSONObject(Automation.prefs(c).getString("lastLocation", "{}")!!)
        val location = if (last.has("lat") && last.has("lng") && System.currentTimeMillis() - last.optLong("locationTime") < 120000)
            Location("rule-cache").apply { latitude = last.getDouble("lat"); longitude = last.getDouble("lng"); accuracy = last.optDouble("accuracy", Double.MAX_VALUE).toFloat(); time = last.getLong("locationTime") }
            else null
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (!rule.has("program")) continue
            if (rule.optJSONObject("program")?.optBoolean("needsLocation", true) == false) run(c, rule, null, null)
            else if (location != null) {
                val distance = FloatArray(1)
                Location.distanceBetween(location.latitude, location.longitude, rule.getDouble("lat"), rule.getDouble("lng"), distance)
                val radius = rule.getDouble("radius")
                val wasInside = Automation.prefs(c).getBoolean("inside:" + rule.getString("id"), false)
                val inside = if (wasInside) distance[0] <= radius + location.accuracy else distance[0] + location.accuracy <= radius
                run(c, rule, inside, location)
            }
        }
    }
    @Synchronized fun run(c: Context, rule: JSONObject, inside: Boolean?, location: Location?) {
        if (!rule.optBoolean("enabled", true)) return
        val program = rule.optJSONObject("program") ?: return
        if (program.optInt("version") != 1) return
        if (program.optBoolean("needsLocation", true) && (!Automation.config(c).optBoolean("locationEnabled") || location == null || location.accuracy > rule.getDouble("radius") || System.currentTimeMillis() - location.time > 120000)) return
        val targets = program.optJSONArray("targets") ?: return
        val now = Calendar.getInstance()
        val session = c.getSharedPreferences("session", Context.MODE_PRIVATE)
        val active = session.getString("id", null) != null
        val values = JSONObject(Automation.prefs(c).getString("snapshot", "{}")!!)
        values.put("session.active", active).put("session.duration_seconds", if (active) (System.currentTimeMillis() - session.getLong("started", System.currentTimeMillis())) / 1000 else 0)
        values.put("session.kind", if (active) session.getString("kind", values.optString("session.kind")) else "")
        values.put("session.note", if (active) session.getString("note", values.optString("session.note")) else "")
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(now.time)
        values.put("calendar.today", today)
        if (active && values.optString("_day") == today && values.optString("_runningId") == session.getString("id", null)) {
            values.put("session.today_seconds", values.optLong("session.today_seconds") + maxOf(0, (System.currentTimeMillis() - values.optLong("_sampleTime", System.currentTimeMillis())) / 1000))
        }
        values.put("notifications.enabled", c.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
        values.put("notifications.exact_allowed", RuleNotifications.exactAllowed(c))
        values.put("notifications.schedule_count", RuleNotifications.count(c))
        val battery = c.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (battery != null) {
            val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1); val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level >= 0 && scale > 0) values.put("device.battery", level * 100.0 / scale)
            values.put("device.charging", battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0)
        }
        val connectivity = c.getSystemService(android.net.ConnectivityManager::class.java)
        values.put("device.connected", connectivity.activeNetwork != null)
        values.put("device.orientation", if (c.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) "landscape" else "portrait")
        val audio = c.getSystemService(android.media.AudioManager::class.java)
        val maximum = audio.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
        values.put("device.volume", if (maximum > 0) audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) * 100.0 / maximum else 0)
        values.put("device.ringer_mode", when (audio.ringerMode) { android.media.AudioManager.RINGER_MODE_SILENT -> "silent"; android.media.AudioManager.RINGER_MODE_VIBRATE -> "vibrate"; else -> "normal" })
        val sample = JSONObject(Automation.prefs(c).getString("lastLocation", "{}")!!)
        if (sample.has("lat") && sample.has("lng")) {
            values.put("location.lat", sample.getDouble("lat")).put("location.lng", sample.getDouble("lng"))
                .put("location.accuracy", sample.optDouble("accuracy"))
                .put("location.sample_age_seconds", maxOf(0, (System.currentTimeMillis() - sample.optLong("locationTime")) / 1000))
        }
        for (i in 0 until minOf(targets.length(), 16)) {
            val target = targets.getJSONObject(i)
            val allowedTargets = Automation.config(c).optJSONArray("knownTargets") ?: continue
            if ((0 until allowedTargets.length()).none { allowedTargets.optString(it) == target.optString("target") }) continue
            val branches = target.getJSONArray("branches")
            var selected = -1
            for (b in 0 until minOf(branches.length(), 128)) {
                if (evaluate(branches.getJSONObject(b).getJSONObject("condition"), inside, active, now, values)) { selected = b; break }
            }
            val key = "branch:${rule.getString("id")}:$i"
            val prefs = Automation.prefs(c)
            if (prefs.contains(key) && prefs.getInt(key, -1) == selected) continue
            if (selected >= 0) {
                val lastRun = prefs.getLong("executed:$key", 0)
                if (System.currentTimeMillis() - lastRun < 1000) continue
                prefs.edit().putLong("executed:$key", System.currentTimeMillis()).putInt(key, selected).commit()
                val actions = branches.getJSONObject(selected).getJSONArray("actions")
                for (a in 0 until minOf(actions.length(), 8)) {
                    val action = actions.getJSONObject(a)
                    // Reserve the edge before emitting actions, preventing feedback loops through snapshots.
                    when (action.optString("action")) {
                        "toast" -> Automation.emit(c, JSONObject().put("time", System.currentTimeMillis()).put("action", "rule_toast").put("title", action.optString("message").take(200)))
                        "setting" -> if (target.optString("target") == "settings_page" && action.optString("key") in listOf("sound", "theme")) {
                            Automation.emit(c, JSONObject().put("time", System.currentTimeMillis()).put("action", "rule_setting").put("title", "Setting changed").put("key", action.getString("key")).put("value", action.getString("value")))
                        }
                        "expense" -> if (target.optString("target") == "budget_page") {
                            Automation.emit(c, JSONObject().put("time", System.currentTimeMillis()).put("action", "purchase").put("title", "Recorded expense").put("amount", action.getString("amount"))
                                .put("currency", action.getString("currency")).put("category", action.getString("category")).put("merchant", action.optString("note")).put("source", "Automation"))
                        }
                        "clock_in" -> if (target.optString("target") == "session_page") {
                            val kind = action.optString("kind")
                            if (kind in listOf("OJT", "Work", "Study", "Personal")) {
                                val adjusted = JSONObject(rule.toString()).put("kind", kind)
                                Automation.applySessionTransition(c, adjusted, true, location)
                            }
                        }
                        "clock_out" -> if (target.optString("target") == "session_page") {
                            Automation.applySessionTransition(c, JSONObject(rule.toString()).put("else", "clock_out"), false, location)
                        }
                        "log" -> if (Automation.config(c).optBoolean("logging")) {
                            val message = action.optString("message").take(200)
                            if (message.isNotBlank()) Automation.emit(c, (location?.let { Automation.locationJson(c, it) } ?: JSONObject())
                                .put("location", rule.getString("name")).put("rule", rule.getString("id"))
                                .put("time", System.currentTimeMillis()).put("action", "custom_log").put("title", message))
                        }
                    }
                }
            }
            if (selected < 0) prefs.edit().putInt(key, selected).commit()
        }
    }
}
