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
    private const val STAY_DWELL_MS = 30 * 60 * 1000L
    private const val STAY_RADIUS_MIN_M = 60f
    private const val STAY_CONTINUITY_MAX_MS = 45 * 60 * 1000L
    private const val STAY_PROMPT_COOLDOWN_MS = 6 * 60 * 60 * 1000L

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
                if (r.optBoolean("enabled", true) && (r.optJSONObject("program")?.optBoolean("needsLocation", true) != false)) fences.add(Geofence.Builder().setRequestId(r.getString("id")).setCircularRegion(r.getDouble("lat"), r.getDouble("lng"), r.getDouble("radius").toFloat()).setExpirationDuration(Geofence.NEVER_EXPIRE).setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT or Geofence.GEOFENCE_TRANSITION_DWELL).setLoiteringDelay(STAY_DWELL_MS.toInt()).build())
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
    private fun ruleUsesLocation(rule: JSONObject) = rule.optJSONObject("program")?.optBoolean("needsLocation", true) != false

    fun requestLocation(c: Context, done: (Location?) -> Unit) {
        MapLocation.request(c) { location, _ -> done(location) }
    }
    fun locationJson(c: Context, location: Location): JSONObject {
        val rules = config(c).optJSONArray("rules") ?: JSONArray(); var name = "${location.latitude}, ${location.longitude}"
        for (i in 0 until rules.length()) { val r = rules.getJSONObject(i); if (!r.optBoolean("enabled", true) || !ruleUsesLocation(r)) continue; val result = FloatArray(1); Location.distanceBetween(location.latitude, location.longitude, r.getDouble("lat"), r.getDouble("lng"), result); if (result[0] <= r.getDouble("radius")) { name = r.getString("name"); break } }
        return JSONObject().put("location", name).put("lat", location.latitude).put("lng", location.longitude).put("accuracy", location.accuracy).put("locationTime", location.time)
    }
    @Synchronized fun updateStay(c: Context, location: Location, minimumDwellMs: Long = 0L): Pair<Boolean, Long> {
        val now = System.currentTimeMillis()
        if (!location.hasAccuracy() || location.accuracy > 100f || now - location.time > 120000L) return Pair(false, 0L)
        val stored = JSONObject(prefs(c).getString("stayState", "{}")!!)
        val hasAnchor = stored.has("lat") && stored.has("lng") && stored.has("started")
        val withinContinuity = hasAnchor && now - stored.optLong("lastTime", 0L) <= STAY_CONTINUITY_MAX_MS
        val sameArea = if (withinContinuity) {
            val dist = FloatArray(1)
            Location.distanceBetween(location.latitude, location.longitude, stored.getDouble("lat"), stored.getDouble("lng"), dist)
            dist[0] <= maxOf(STAY_RADIUS_MIN_M, location.accuracy)
        } else false
        if (sameArea) {
            var started = stored.optLong("started", now)
            if (minimumDwellMs > 0L && now - started < minimumDwellMs) {
                started = now - minimumDwellMs
            }
            stored.put("started", started).put("lastTime", now)
            prefs(c).edit().putString("stayState", stored.toString()).commit()
            return Pair(false, maxOf(0L, now - started))
        }
        val started = if (minimumDwellMs > 0L) now - minimumDwellMs else now
        val freshState = JSONObject()
            .put("lat", location.latitude)
            .put("lng", location.longitude)
            .put("started", started)
            .put("lastTime", now)
            .put("logged30", false)
            .put("prompted", false)
        prefs(c).edit().putString("stayState", freshState.toString()).commit()
        return Pair(true, maxOf(0L, now - started))
    }

    fun dwellMinutes(c: Context): Int {
        val stored = JSONObject(prefs(c).getString("stayState", "{}")!!)
        if (!stored.has("started") || !stored.has("lastTime")) return 0
        val now = System.currentTimeMillis()
        if (now - stored.optLong("lastTime", 0L) > STAY_CONTINUITY_MAX_MS) return 0
        return ((now - stored.optLong("started", now)) / 60_000L).toInt().coerceAtLeast(0)
    }

    private fun insideAnyRule(c: Context, location: Location): Boolean {
        val rules = config(c).optJSONArray("rules") ?: return false
        val dist = FloatArray(1)
        for (i in 0 until rules.length()) {
            val r = rules.getJSONObject(i)
            if (!r.optBoolean("enabled", true) || !ruleUsesLocation(r)) continue
            Location.distanceBetween(location.latitude, location.longitude, r.getDouble("lat"), r.getDouble("lng"), dist)
            if (dist[0] <= r.getDouble("radius")) return true
        }
        return false
    }

    fun logLocation(c: Context, location: Location) {
        val now = System.currentTimeMillis()
        if (now - location.time > 120000L) return
        val (moved, dwellMs) = updateStay(c, location)
        val base = locationJson(c, location).put("time", now)
        prefs(c).edit().putString("lastLocation", JSONObject(base.toString()).put("action", "location").put("title", "Visited").toString()).commit()
        if (!config(c).optBoolean("logging") || RuntimeEvents.samplesPaused(c)) return
        if (moved) {
            emit(c, JSONObject(base.toString()).put("action", "location").put("title", "Visited"))
            return
        }
        if (dwellMs >= STAY_DWELL_MS) {
            val stay = JSONObject(prefs(c).getString("stayState", "{}")!!)
            if (!stay.optBoolean("logged30")) {
                stay.put("logged30", true)
                prefs(c).edit().putString("stayState", stay.toString()).commit()
                emit(c, JSONObject(base.toString()).put("action", "location_stay").put("title", "Stayed 30+ min").put("dwellMinutes", (dwellMs / 60_000L).toInt()))
            }
            val hasRunningSession = c.getSharedPreferences("session", Context.MODE_PRIVATE).getString("id", null) != null
            val cooldownElapsed = now - prefs(c).getLong("lastStayPromptAt", 0L) >= STAY_PROMPT_COOLDOWN_MS
            if (!stay.optBoolean("prompted") && !hasRunningSession && !insideAnyRule(c, location) && cooldownElapsed) {
                val posted = RuleNotifications.post(
                    c,
                    "Still in this area?",
                    "Stayed 30+ min here. Open FrekiHub to start a session or save a place rule.",
                    "stay:${stay.optLong("started", now)}"
                )
                if (posted) {
                    stay.put("prompted", true)
                    prefs(c).edit().putString("stayState", stay.toString()).putLong("lastStayPromptAt", now).commit()
                }
            }
        }
    }
    fun recheck(c: Context, location: Location) {
        val rules = config(c).optJSONArray("rules") ?: return
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (!ruleUsesLocation(rule)) continue
            val distance = FloatArray(1)
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
        for (fence in event.triggeringGeofences.orEmpty()) for (i in 0 until rules.length()) { val rule = rules.getJSONObject(i); if (rule.getString("id") == fence.requestId) { val dwell = event.geofenceTransition == Geofence.GEOFENCE_TRANSITION_DWELL; val enter = event.geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER || dwell; if (dwell) { event.triggeringLocation?.let { Automation.updateStay(c, it, 30 * 60 * 1000L) } } else if (enter && Automation.prefs(c).getBoolean("inside:" + rule.getString("id"), false)) continue; Automation.transition(c, rule, enter, event.triggeringLocation); if (!enter || event.triggeringLocation?.let { it.accuracy <= rule.getDouble("radius") } == true) Automation.prefs(c).edit().putBoolean("inside:" + rule.getString("id"), enter).commit() } }
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

