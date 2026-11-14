package com.frekihub.freki_hub

import android.Manifest
import android.content.Intent
import android.content.ComponentName
import android.app.NotificationManager
import android.net.Uri
import android.provider.Settings
import android.provider.Telephony
import org.json.JSONObject
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        // Re-arm after force-stop or changes to Android alarm access.
        RuleNotifications.sync(this, restore = true)
    }
    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val readySounds = mutableSetOf<Int>()
    private var pendingResult: MethodChannel.Result? = null
    private var startData: Map<*, *>? = null
    private var locationResult: MethodChannel.Result? = null
    private var receiptPermissionResult: MethodChannel.Result? = null
private var smsPermissionResult: MethodChannel.Result? = null
    private var reminderPermissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frekihub/session").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("session", MODE_PRIVATE)
            try { when (call.method) {
                "cacheSession" -> result.success(cacheSession(call.arguments as Map<*, *>))
                "permissionStatus" -> {
                    val notifications = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
                    result.success(mapOf(
                        "start" to notifications,
                        "receiptNotificationPermission" to TransactionNotifications.allowed(this),
                        "reminderPermission" to notifications,
                        "locationPermission" to (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED),
                        "backgroundPermission" to Automation.allowed(this),
                        "notificationPermission" to getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(ComponentName(this, PurchaseListener::class.java)),
                        "smsPermission" to (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED),
                        "exactReminderPermission" to RuleNotifications.exactAllowed(this),
                        "overlayPermission" to Settings.canDrawOverlays(this)
                    ))
                }
                "permissionSettings" -> {
                    val method = call.arguments as? String
                    val settings = when (method) {
                        "start", "receiptNotificationPermission", "reminderPermission" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        "locationPermission", "backgroundPermission" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        "notificationPermission" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        "smsPermission" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        "exactReminderPermission" -> Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                        "overlayPermission" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        else -> null
                    }
                    if (settings == null) result.error("permission", "Unknown permission settings", null)
                    else {
                        startActivity(settings)
                        result.success(if (method == "receiptNotificationPermission") TransactionNotifications.allowed(this) else null)
                    }
                }
                "overlayAllowed" -> result.success(Settings.canDrawOverlays(this))
                "overlayPermission" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "notificationSoundSettings" -> {
                    try { NotificationSoundSettings.open(this, call.arguments as String); result.success(null) }
                    catch (e: Exception) { result.error("notification_sound", e.message, null) }
                }
                "transactionSaved" -> result.success(TransactionNotifications.post(this, call.arguments as Map<*, *>))
                "purchaseDestination" -> { val page = intent.getStringExtra("openPage"); intent.removeExtra("openPage"); result.success(page) }
                "receiptNotificationsAllowed" -> result.success(TransactionNotifications.allowed(this))
                "receiptNotificationPermission" -> {
                    if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (receiptPermissionResult != null || pendingResult != null) result.success(false)
                        else { receiptPermissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 75) }
                    } else {
                        val allowed = TransactionNotifications.allowed(this)
                        if (!allowed) startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(allowed)
                    }
                }
                "automationAppState" -> {
                    val snapshot = org.json.JSONObject(Automation.prefs(this).getString("snapshot", "{}")!!)
                    snapshot.put("app.foreground", call.arguments as Boolean)
                    Automation.prefs(this).edit().putString("snapshot", snapshot.toString()).commit()
                    RuleProgram.refresh(this); result.success(null)
                }
                "automationConfig" -> { Automation.configure(this, call.arguments as String); result.success(null) }
                "automationReset" -> { RuntimeEvents.reset(this); Automation.prefs(this).edit().clear().commit(); Automation.configure(this, "{}"); result.success(null) }
                "automationEvents" -> result.success(RuntimeEvents.read(this))
                "automationAck" -> { Automation.acknowledge(this, (call.arguments as List<*>).filterIsInstance<String>()); result.success(null) }
                "automationStatus" -> result.success(mapOf(
                    "location" to (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED),
                    "background" to Automation.allowed(this),
                    "notifications" to getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(ComponentName(this, PurchaseListener::class.java)),
                    "pending_count" to RuntimeEvents.pending(this),
                    "logging_paused" to RuntimeEvents.samplesPaused(this),
                    "timer_available" to !Automation.prefs(this).contains("timerDeliveryError")
                ))
                "locationPermission" -> {
                    if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (locationResult != null) result.error("busy", "A permission request is already open", null)
                    else { locationResult = result; requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 74) }
                }
                "backgroundPermission" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                "smsPermission" -> {
                    if (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (smsPermissionResult != null) result.error("busy", "A permission request is already open", null)
                    else { smsPermissionResult = result; requestPermissions(arrayOf(Manifest.permission.READ_SMS), 77) }
                }
                "notificationPermission" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                "mapCurrentLocation" -> MapLocation.request(this) { location, error ->
                    if (location == null) result.error("location", error, null)
                    else result.success(org.json.JSONObject().put("lat", location.latitude).put("lng", location.longitude).put("accuracy", location.accuracy).put("locationTime", location.time).toString())
                }
                "currentLocation" -> Automation.requestLocation(this) { location -> if (location == null) result.error("location", "No fresh location available. Enable precise location and try again.", null) else result.success(Automation.locationJson(this, location).toString()) }
                "notificationApps" -> {
                    val apps = packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0).distinctBy { it.activityInfo.packageName }.map { mapOf("name" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName) }.sortedBy { it["name"] }
                    result.success(apps)
                }
                "sound" -> {
                    try { playSound(call.arguments as? String); result.success(null) }
                    catch (e: Exception) { result.error("sound", e.message, null) }
                }
                "reminderPermission" -> {
                    if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (reminderPermissionResult != null) result.error("busy", "A permission request is already open", null)
                        else { reminderPermissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 76) }
                    } else {
                        val allowed = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
                        if (!allowed) startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(allowed)
                    }
                }
                "exactReminderPermission" -> {
                    if (!RuleNotifications.exactAllowed(this)) {
                        startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                    }
                    result.success(RuleNotifications.exactAllowed(this))
                }
                "reminderStatus" -> { result.success(mapOf("exact" to RuleNotifications.exactAllowed(this), "enabled" to getSystemService(NotificationManager::class.java).areNotificationsEnabled())) }
                "start" -> {
                    val data = call.arguments as Map<*, *>
                    if (!cacheSession(data)) { result.success(false); return@setMethodCallHandler }
                    if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        startData = data; pendingResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 73)
                    } else if (!getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(false)
                    } else { result.success(startTimer(data)) }
                }
                "stop" -> { SessionService.stopTimer(this); prefs.edit().remove("id").commit(); Automation.prefs(this).edit().remove("activeRule").commit(); result.success(null) }
                "pending" -> {
                    val id = prefs.getString("pendingId", null)
                    result.success(if (id == null) null else mutableMapOf<String, Any?>("id" to id, "ended" to prefs.getLong("pendingEnd", 0)).apply {
                        if (prefs.contains("pendingNote")) put("note", prefs.getString("pendingNote", ""))
                        if (prefs.contains("pendingPosition")) put("position", prefs.getString("pendingPosition", null))
                    })
                }
                "acknowledge" -> { check(prefs.edit().remove("pendingId").remove("pendingEnd").remove("pendingNote").remove("pendingPosition").commit()); result.success(null) }
                "smsScan" -> {
                    if (checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) { result.error("permission", "SMS permission required", null); return@setMethodCallHandler }
                    val since = (call.arguments as? Number)?.toLong() ?: Automation.prefs(this).getLong("smsLastScan", System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000)
                    var maxDate = since
                    val cursor = contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("_id", "address", "body", "date"), "date > ?", arrayOf(since.toString()), "date ASC")
                    cursor?.use {
                        val idIdx = it.getColumnIndexOrThrow("_id")
                        val addrIdx = it.getColumnIndexOrThrow("address")
                        val bodyIdx = it.getColumnIndexOrThrow("body")
                        val dateIdx = it.getColumnIndexOrThrow("date")
                        while (it.moveToNext()) {
                            val body = it.getString(bodyIdx) ?: continue
                            val transaction = FinanceNotificationParser.parse(body) ?: continue
                            val date = it.getLong(dateIdx)
                            if (date > maxDate) maxDate = date
                            val reference = Regex("(?i)(?:reference|ref|transaction)(?:\\s*(?:no|number|id))?[.:#\\s]+([A-Z0-9-]{6,})").find(body)?.groupValues?.get(1)
                            val idPrefix = if (transaction.kind == "income") "income" else "purchase"
                            val smsId = it.getString(idIdx)
                            val id = "sms:$smsId"
                            val counterparty = transaction.counterparty
                            val eventTitle = when (transaction.kind) {
                                "income" -> if (counterparty == "Not specified") "Received income" else "Received income · $counterparty"
                                else -> if (counterparty == "Item not specified") "Purchased · item not specified" else "Purchased at $counterparty"
                            }
                            val event = JSONObject(Automation.prefs(this).getString("lastLocation", "{}")!!)
                                .put("id", "$idPrefix:$id")
                                .put("time", date)
                                .put("action", "purchase")
                                .put("kind", transaction.kind)
                                .put("title", eventTitle)
                                .put("merchant", counterparty)
                                .put("amount", transaction.amount)
                                .put("currency", transaction.currency)
                                .put("package", "sms")
                                .put("reference", reference ?: "")
                            val addr = it.getString(addrIdx) ?: "SMS"
                            event.put("source", addr)
                            val locationTime = event.optLong("locationTime", 0L)
                            if (System.currentTimeMillis() - locationTime > 120000L) { event.remove("lat"); event.remove("lng"); event.put("location", "Location unavailable") }
                            Automation.emit(this, event)
                        }
                    }
                    Automation.prefs(this).edit().putLong("smsLastScan", maxDate).commit()
                    result.success(maxDate)
                }
                else -> result.notImplemented()
            } } catch (error: Exception) {
                android.util.Log.w("FrekiHub", "Native operation failed: ${call.method}", error)
                result.error("native_operation", "Could not complete this operation. Your pending actions are retained for retry.", null)
            }
        }
    }
    private fun playSound(name: String?) {
        val assetName = when (name) {
            "click" -> "clock-in"
            "transition" -> "clock-out"
            "clock-in", "clock-out" -> name
            else -> return
        }
        val volume = if (name == "click" || name == "transition") 0.25f else 0.7f
        val rate = if (name == "click") 1.4f else if (name == "transition") 0.85f else 1f
        val pool = soundPool ?: SoundPool.Builder().setMaxStreams(2)
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .build().also { created ->
                soundPool = created
                created.setOnLoadCompleteListener { loadedPool, id, status ->
                    if (status == 0) {
                        readySounds.add(id)
                        val key = soundIds.entries.firstOrNull { it.value == id }?.key
                        val level = if (key == "click" || key == "transition") 0.25f else 0.7f
                        val speed = if (key == "click") 1.4f else if (key == "transition") 0.85f else 1f
                        loadedPool.play(id, level, level, 1, 0, speed)
                    }
                }
            }
        val existing = soundIds[name]
        if (existing != null) {
            if (existing in readySounds) pool.play(existing, volume, volume, 1, 0, rate)
        } else {
            val asset = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/sounds/$assetName.wav")
            assets.openFd(asset).use { soundIds[name] = pool.load(it, 1) }
        }
    }
    override fun onDestroy() {
        soundPool?.release(); soundPool = null; soundIds.clear(); readySounds.clear()
        super.onDestroy()
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
    private fun startTimer(data: Map<*, *>): Boolean {
        val id = data["id"] as String
        if (getSharedPreferences("session", MODE_PRIVATE).getString("pendingId", null) == id) return false
        val intent = Intent(this, SessionService::class.java).putExtra("id", id).putExtra("started", (data["started"] as Number).toLong()).putExtra("day", data["day"] as String).putExtra("kind", data["kind"] as? String ?: "OJT").putExtra("note", data["note"] as? String ?: "")
        return SessionService.startSafely(this, intent, id)
    }
    private fun cacheSession(data: Map<*, *>): Boolean {
        val prefs = getSharedPreferences("session", MODE_PRIVATE)
        val id = data["id"] as String
        if (prefs.getString("pendingId", null) == id) return false
        return prefs.edit().putString("id", id)
            .putLong("started", (data["started"] as Number).toLong())
            .putString("kind", data["kind"] as? String ?: "OJT")
            .putString("note", data["note"] as? String ?: "").commit()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 73) {
            val approved = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val started = approved && startData?.let { startTimer(it) } == true
            pendingResult?.success(started); pendingResult = null; startData = null
        }
        if (requestCode == 74) { locationResult?.success(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED); locationResult = null }
        if (requestCode == 75) { receiptPermissionResult?.success(TransactionNotifications.allowed(this)); receiptPermissionResult = null }
        if (requestCode == 76) { reminderPermissionResult?.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled()); reminderPermissionResult = null }
        if (requestCode == 77) { smsPermissionResult?.success(checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED); smsPermissionResult = null }
    }
}
