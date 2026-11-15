package com.frekihub.freki_hub

import android.Manifest
import android.app.*
import android.app.job.*
import android.content.*
import android.content.pm.PackageManager
import android.location.*
import android.os.*
import android.provider.Settings
import android.service.notification.*
import com.google.android.gms.location.*
import org.json.*
import java.util.UUID

object Automation {
    fun prefs(c: Context) = c.getSharedPreferences("automation", Context.MODE_PRIVATE)
    @Synchronized fun emit(c: Context, event: JSONObject) {
        RuntimeEvents.emit(c, event)
    }
    @Synchronized fun acknowledge(c: Context, ids: List<String>) {
        RuntimeEvents.acknowledge(c, ids)
    }
    fun config(c: Context) = JSONObject(prefs(c).getString("config", "{}")!!)
    fun allowed(c: Context) = c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && c.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    fun configure(c: Context, raw: String) {
        val payload = JSONObject(raw)
        payload.optJSONObject("snapshot")?.let { prefs(c).edit().putString("snapshot", it.toString()).commit() }
        payload.remove("snapshot")
        val json = payload.toString()
        val fingerprint = json + ":" + allowed(c)
        if (prefs(c).getString("configured", null) == fingerprint) { RuleNotifications.sync(c); RuleProgram.refresh(c); return }
        val previousConfig = config(c)
        val nextConfig = JSONObject(json)
        val previousRules = previousConfig.optJSONArray("rules") ?: JSONArray()
        val nextRules = nextConfig.optJSONArray("rules") ?: JSONArray()
        for (i in 0 until nextRules.length()) {
            val rule = nextRules.getJSONObject(i)
            val old = (0 until previousRules.length()).map { previousRules.getJSONObject(it) }.firstOrNull { it.optString("id") == rule.optString("id") }
            if (old == null || old.optJSONObject("program")?.toString() != rule.optJSONObject("program")?.toString() || old.optBoolean("enabled", true) != rule.optBoolean("enabled", true)) {
                val edit = prefs(c).edit()
                for (index in 0..15) edit.remove("branch:${rule.getString("id")}:$index").remove("executed:branch:${rule.getString("id")}:$index")
                edit.commit()
            }
            if (!previousConfig.optBoolean("locationEnabled") || old == null || old.optJSONObject("program")?.toString() != rule.optJSONObject("program")?.toString() || old.optDouble("lat") != rule.optDouble("lat") || old.optDouble("lng") != rule.optDouble("lng") || old.optDouble("radius") != rule.optDouble("radius")) prefs(c).edit().remove("inside:" + rule.getString("id")).commit()
        }
        prefs(c).edit().putString("config", json).commit()
        RuleNotifications.sync(c)
        val config = config(c)
        val intent = PendingIntent.getBroadcast(c, 91, Intent(c, ZoneReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
        val client = LocationServices.getGeofencingClient(c)
        client.removeGeofences(intent).addOnCompleteListener {
            if (prefs(c).getString("config", null) != json) return@addOnCompleteListener
            if (!config.optBoolean("locationEnabled") || !allowed(c)) return@addOnCompleteListener
            val rules = config.optJSONArray("rules") ?: JSONArray()
            val fences = mutableListOf<Geofence>()
            for (i in 0 until rules.length()) {
                val r = rules.getJSONObject(i)
                if (r.optBoolean("enabled", true) && (r.optJSONObject("program")?.optBoolean("needsLocation", true) != false)) fences.add(Geofence.Builder().setRequestId(r.getString("id")).setCircularRegion(r.getDouble("lat"), r.getDouble("lng"), r.getDouble("radius").toFloat()).setExpirationDuration(Geofence.NEVER_EXPIRE).setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT).build())
            }
            if (fences.isNotEmpty()) {
                try { client.addGeofences(GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofences(fences).build(), intent).addOnSuccessListener { prefs(c).edit().putString("configured", fingerprint).commit() }.addOnFailureListener { emit(c, JSONObject().put("time", System.currentTimeMillis()).put("action", "error").put("title", "Location rules unavailable").put("details", it.message)) } }
                catch (e: SecurityException) { }
            } else prefs(c).edit().putString("configured", fingerprint).commit()
        }
        if (!config.optBoolean("locationEnabled") || !allowed(c) || (config.optJSONArray("rules")?.length() ?: 0) == 0) prefs(c).edit().putString("configured", fingerprint).commit()
        val scheduler = c.getSystemService(JobScheduler::class.java)
        val hasPrograms = (0 until nextRules.length()).any { nextRules.getJSONObject(it).optBoolean("enabled", true) && nextRules.getJSONObject(it).has("program") }
        if ((config.optBoolean("locationEnabled") && allowed(c)) || hasPrograms) scheduler.schedule(JobInfo.Builder(91, ComponentName(c, LocationLogJob::class.java)).setPeriodic(15 * 60 * 1000L).setPersisted(true).build()) else scheduler.cancel(91)
        RuleProgram.refresh(c)
    }
    fun requestLocation(c: Context, done: (Location?) -> Unit) {
        MapLocation.request(c) { location, _ -> done(location) }
    }
    fun locationJson(c: Context, location: Location): JSONObject {
        val rules = config(c).optJSONArray("rules") ?: JSONArray(); var name = "${location.latitude}, ${location.longitude}"
        for (i in 0 until rules.length()) { val r = rules.getJSONObject(i); val result = FloatArray(1); Location.distanceBetween(location.latitude, location.longitude, r.getDouble("lat"), r.getDouble("lng"), result); if (result[0] <= r.getDouble("radius")) { name = r.getString("name"); break } }
        return JSONObject().put("location", name).put("lat", location.latitude).put("lng", location.longitude).put("accuracy", location.accuracy).put("locationTime", location.time)
    }
    fun logLocation(c: Context, location: Location) {
        if (System.currentTimeMillis() - location.time > 120000) return
        val event = locationJson(c, location).put("time", System.currentTimeMillis()).put("action", "location").put("title", "Visited")
        prefs(c).edit().putString("lastLocation", event.toString()).commit()
        if (config(c).optBoolean("logging") && !RuntimeEvents.samplesPaused(c)) emit(c, event)
    }
    fun recheck(c: Context, location: Location) {
        val rules = config(c).optJSONArray("rules") ?: return
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i); val distance = FloatArray(1)
            Location.distanceBetween(location.latitude, location.longitude, rule.getDouble("lat"), rule.getDouble("lng"), distance)
            val radius = rule.getDouble("radius")
            if (location.accuracy > radius || System.currentTimeMillis() - location.time > 120000) continue
            val wasInside = prefs(c).getBoolean("inside:" + rule.getString("id"), false)
            val inside = if (wasInside) distance[0] <= radius + location.accuracy else distance[0] + location.accuracy <= radius
            if (rule.has("program")) RuleProgram.run(c, rule, inside, location)
            if (inside != wasInside) { transition(c, rule, inside, location); prefs(c).edit().putBoolean("inside:" + rule.getString("id"), inside).commit() }
        }
    }
    @Synchronized fun transition(c: Context, rule: JSONObject, enter: Boolean, location: Location?) {
        if (rule.has("program")) RuleProgram.run(c, rule, enter, location)
        else applySessionTransition(c, rule, enter, location)
    }
    @Synchronized fun applySessionTransition(c: Context, rule: JSONObject, enter: Boolean, location: Location?) {
        val config = config(c); if ((!rule.has("program") && !config.optBoolean("locationEnabled")) || !rule.optBoolean("enabled", true)) return
        val p = c.getSharedPreferences("session", Context.MODE_PRIVATE)
        val event = (location?.let { locationJson(c, it) } ?: JSONObject()).put("location", rule.getString("name")).put("time", System.currentTimeMillis()).put("rule", rule.getString("id"))
        if (enter) {
            if (p.getString("id", null) != null || prefs(c).contains("activeRule")) return
            if (rule.optJSONObject("program")?.optBoolean("needsLocation", true) != false && (location == null || location.accuracy > rule.getDouble("radius") || System.currentTimeMillis() - location.time > 120000)) return
            val id = UUID.randomUUID().toString(); val started = System.currentTimeMillis()
            prefs(c).edit().putString("activeRule", rule.getString("id")).commit()
            p.edit().putString("id", id).putLong("started", started).putString("kind", rule.optString("kind", "OJT")).putString("note", "Automatic · " + rule.getString("name")).commit()
            emit(c, event.put("action", "auto_clock_in").put("title", "Clocked in").put("sessionId", id).put("started", started).put("kind", rule.optString("kind", "OJT")))
            // The geofence exemption allows a foreground timer after a location transition.
            val timer = Intent(c, SessionService::class.java).putExtra("id", id).putExtra("started", started)
            SessionService.startSafely(c, timer, id)
        } else if (prefs(c).getString("activeRule", null) == rule.getString("id") && rule.optString("else", "continue") == "clock_out") {
            val id = p.getString("id", null) ?: return
            emit(c, event.put("action", "auto_clock_out").put("title", "Clocked out").put("sessionId", id))
            prefs(c).edit().remove("activeRule").commit(); p.edit().remove("id").commit(); SessionService.stopTimer(c)
        } else if (config.optBoolean("logging")) emit(c, event.put("action", "location_exit").put("title", "Left"))
    }
}

class ZoneReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val rules = Automation.config(c).optJSONArray("rules") ?: return
        for (fence in event.triggeringGeofences.orEmpty()) for (i in 0 until rules.length()) { val rule = rules.getJSONObject(i); if (rule.getString("id") == fence.requestId) { val enter = event.geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER; if (enter && Automation.prefs(c).getBoolean("inside:" + rule.getString("id"), false)) continue; Automation.transition(c, rule, enter, event.triggeringLocation); if (!enter || event.triggeringLocation?.let { it.accuracy <= rule.getDouble("radius") } == true) Automation.prefs(c).edit().putBoolean("inside:" + rule.getString("id"), enter).commit() } }
    }
}
class LocationLogJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        RuleProgram.refresh(this)
        if (!Automation.config(this).optBoolean("locationEnabled") || !Automation.allowed(this)) return false
        Automation.requestLocation(this) { location -> if (location != null) { Automation.logLocation(this, location); Automation.recheck(this, location) }; jobFinished(params, false) }
        return true
    }
    override fun onStopJob(params: JobParameters) = true
}
class AutomationBootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (intent.action !in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED, "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) return
        Automation.prefs(c).edit().remove("configured").commit()
        Automation.configure(c, Automation.config(c).toString())
        RuleNotifications.sync(c, restore = true)
    }
}
class PurchaseListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val config = Automation.config(this)
        if (!config.optBoolean("purchases")) return
        val apps = config.optJSONArray("apps") ?: return
        if ((0 until apps.length()).none { apps.getString(it) == sbn.packageName }) return
        val extras = sbn.notification.extras
        val textParts = mutableListOf<String>()
        listOf(
            Notification.EXTRA_TITLE,
            Notification.EXTRA_TEXT,
            Notification.EXTRA_BIG_TEXT,
            Notification.EXTRA_SUB_TEXT,
            Notification.EXTRA_SUMMARY_TEXT,
        ).forEach { key -> extras.getCharSequence(key)?.toString()?.let(textParts::add) }
        extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.forEach { textParts.add(it.toString()) }
        extras.getParcelableArray("android.messages")?.forEach { message ->
            (message as? Bundle)?.getCharSequence("text")?.toString()?.let(textParts::add)
        }
        val text = textParts.map(String::trim).filter(String::isNotEmpty).distinct().joinToString(" ")
        val transaction = FinanceNotificationParser.parse(text) ?: return
        val reference = Regex("(?i)(?:reference|ref|transaction)(?:\\s*(?:no|number|id))?[.:#\\s]+([A-Z0-9-]{6,})").find(text)?.groupValues?.get(1)
        val idPrefix = if (transaction.kind == "income") "income" else "purchase"
        val id = sbn.packageName + ":" + (reference ?: (sbn.key + ":" + sbn.postTime))
        val counterparty = transaction.counterparty
        val fingerprint = sbn.key + ":" + transaction.kind + ":" + transaction.currency + ":" + transaction.amount + ":" + counterparty
        val previous = JSONObject(Automation.prefs(this).getString("lastPurchase", "{}")!!)
        if (previous.optString("fingerprint") == fingerprint && System.currentTimeMillis() - previous.optLong("time") < 120000) return
        Automation.prefs(this).edit().putString("lastPurchase", JSONObject().put("fingerprint", fingerprint).put("time", System.currentTimeMillis()).toString()).commit()
        val eventTitle = when (transaction.kind) {
            "income" -> if (counterparty == "Not specified") "Received income" else "Received income · $counterparty"
            else -> if (counterparty == "Item not specified") "Purchased · item not specified" else "Purchased at $counterparty"
        }
        val event = JSONObject(Automation.prefs(this).getString("lastLocation", "{}")!!)
            .put("id", "$idPrefix:$id")
            .put("time", sbn.postTime)
            .put("action", "purchase")
            .put("kind", transaction.kind)
            .put("title", eventTitle)
            .put("merchant", counterparty)
            .put("amount", transaction.amount)
            .put("currency", transaction.currency)
            .put("package", sbn.packageName)
            .put("reference", reference ?: "")
        if (System.currentTimeMillis() - event.optLong("locationTime", 0) > 120000) { event.remove("lat"); event.remove("lng"); event.put("location", "Location unavailable") }
        val appLabel = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString() } catch (e: Exception) { sbn.packageName }
        val sourceName = FinanceNotificationParser.resolveSource(text, appLabel, sbn.packageName)
        event.put("source", sourceName); Automation.emit(this, event)
    }
}

