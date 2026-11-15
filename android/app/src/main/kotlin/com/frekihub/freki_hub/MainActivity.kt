package com.frekihub.freki_hub

import android.Manifest
import android.content.Intent
import android.content.ComponentName
import android.app.NotificationManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import org.json.JSONObject
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.AudioAttributes
import android.media.SoundPool
import java.io.ByteArrayOutputStream
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
                "walletAppIcons" -> {
                    val names = (call.arguments as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
                    Thread {
                        val icons = resolveWalletAppIcons(names)
                        Handler(Looper.getMainLooper()).post { result.success(icons) }
                    }.start()
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
                    if (!Automation.config(this).optBoolean("sms")) {
                        result.success(0L)
                        return@setMethodCallHandler
                    }
                    if (checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
                        result.error("permission", "SMS permission required", null)
                        return@setMethodCallHandler
                    }
                    val appContext = applicationContext
                    val mainHandler = Handler(Looper.getMainLooper())
                    val argSince = (call.arguments as? Number)?.toLong()
                    Thread {
                        try {
                            val automationPrefs = Automation.prefs(appContext)
                            val since = argSince ?: automationPrefs.getLong(
                                "smsLastScan",
                                System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
                            )
                            var maxDate = since
                            val referencePattern = Regex(
                                "(?i)(?:reference|ref|transaction)(?:\\s*(?:no|number|id))?[.:#\\s]+([A-Z0-9-]{6,})"
                            )
                            val lastLocationRaw = automationPrefs.getString("lastLocation", "{}") ?: "{}"
                            val cursor = appContext.contentResolver.query(
                                Telephony.Sms.Inbox.CONTENT_URI,
                                arrayOf("_id", "address", "body", "date"),
                                "date > ?",
                                arrayOf(since.toString()),
                                "date ASC"
                            )
                            cursor?.use {
                                val idIdx = it.getColumnIndexOrThrow("_id")
                                val addrIdx = it.getColumnIndexOrThrow("address")
                                val bodyIdx = it.getColumnIndexOrThrow("body")
                                val dateIdx = it.getColumnIndexOrThrow("date")
                                while (it.moveToNext()) {
                                    val date = it.getLong(dateIdx)
                                    if (date > maxDate) maxDate = date
                                    val body = it.getString(bodyIdx) ?: continue
                                    val transaction = FinanceNotificationParser.parse(body) ?: continue
                                    val reference = referencePattern.find(body)?.groupValues?.get(1)
                                    val idPrefix = if (transaction.kind == "income") "income" else "purchase"
                                    val smsId = it.getString(idIdx)
                                    val id = "sms:$smsId"
                                    val counterparty = transaction.counterparty
                                    val eventTitle = when (transaction.kind) {
                                        "income" -> if (counterparty == "Not specified") "Received income" else "Received income · $counterparty"
                                        else -> if (counterparty == "Item not specified") "Purchased · item not specified" else "Purchased at $counterparty"
                                    }
                                    val event = JSONObject(lastLocationRaw)
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
                                    event.put("source", FinanceNotificationParser.resolveSource(body, addr, "sms"))
                                    val locationTime = event.optLong("locationTime", 0L)
                                    if (System.currentTimeMillis() - locationTime > 120000L) {
                                        event.remove("lat")
                                        event.remove("lng")
                                        event.put("location", "Location unavailable")
                                    }
                                    Automation.emit(appContext, event)
                                }
                            }
                            automationPrefs.edit().putLong("smsLastScan", maxDate).commit()
                            mainHandler.post { result.success(maxDate) }
                        } catch (error: Exception) {
                            android.util.Log.w("FrekiHub", "Native operation failed: smsScan", error)
                            mainHandler.post {
                                result.error(
                                    "native_operation",
                                    "Could not complete this operation. Your pending actions are retained for retry.",
                                    null
                                )
                            }
                        }
                    }.start()
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

    private fun resolveWalletAppIcons(names: List<String>): Map<String, ByteArray> {
        if (names.isEmpty()) return emptyMap()
        val launcherApps = try {
            packageManager.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
                0
            ).distinctBy { it.activityInfo.packageName }.map { info ->
                Triple(
                    info.loadLabel(packageManager).toString().trim(),
                    info.activityInfo.packageName.lowercase(),
                    info
                )
            }
        } catch (_: Exception) {
            return emptyMap()
        }
        val result = mutableMapOf<String, ByteArray>()
        for (rawName in names) {
            val parts = rawName.split("|", limit = 2)
            val key = parts[0].trim()
            if (key.isEmpty()) continue
            val pkgHint = parts.getOrNull(1)?.trim()?.lowercase()
            val lower = key.lowercase()
            if (pkgHint.isNullOrEmpty() && (lower == "cash" || lower == "bank" || lower == "card" || lower == "other")) continue
            val aliases = walletAliases(lower)
            val match = (if (!pkgHint.isNullOrEmpty()) {
                launcherApps.firstOrNull { (_, pkg, _) -> pkg == pkgHint }
            } else null) ?: launcherApps.firstOrNull { (label, _, _) ->
                aliases.any { alias -> label.equals(alias, ignoreCase = true) }
            } ?: launcherApps.firstOrNull { (label, pkg, _) ->
                aliases.any { alias ->
                    label.lowercase().contains(alias) || pkg.contains(alias.replace(" ", ""))
                }
            } ?: continue
            try {
                val drawable = match.third.loadIcon(packageManager).mutate()
                val rawSize = 144
                val rawBitmap = Bitmap.createBitmap(rawSize, rawSize, Bitmap.Config.ARGB_8888)
                val rawCanvas = Canvas(rawBitmap)
                drawable.setBounds(0, 0, rawSize, rawSize)
                drawable.draw(rawCanvas)

                val pixels = IntArray(rawSize * rawSize)
                rawBitmap.getPixels(pixels, 0, rawSize, 0, 0, rawSize, rawSize)
                var minX = rawSize
                var minY = rawSize
                var maxX = -1
                var maxY = -1
                for (y in 0 until rawSize) {
                    val row = y * rawSize
                    for (x in 0 until rawSize) {
                        val alpha = (pixels[row + x] ushr 24) and 0xFF
                        if (alpha > 16) {
                            if (x < minX) minX = x
                            if (x > maxX) maxX = x
                            if (y < minY) minY = y
                            if (y > maxY) maxY = y
                        }
                    }
                }

                val outSize = 96
                val outBitmap = Bitmap.createBitmap(outSize, outSize, Bitmap.Config.ARGB_8888)
                val outCanvas = Canvas(outBitmap)
                if (maxX >= minX && maxY >= minY) {
                    val cropW = (maxX - minX + 1).toFloat()
                    val cropH = (maxY - minY + 1).toFloat()
                    val scale = minOf(outSize / cropW, outSize / cropH)
                    val dstW = cropW * scale
                    val dstH = cropH * scale
                    val left = (outSize - dstW) / 2f
                    val top = (outSize - dstH) / 2f
                    val src = android.graphics.Rect(minX, minY, maxX + 1, maxY + 1)
                    val dst = android.graphics.RectF(left, top, left + dstW, top + dstH)
                    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.FILTER_BITMAP_FLAG)
                    outCanvas.drawBitmap(rawBitmap, src, dst, paint)
                } else {
                    outCanvas.drawBitmap(rawBitmap, null, android.graphics.RectF(0f, 0f, outSize.toFloat(), outSize.toFloat()), null)
                }
                rawBitmap.recycle()

                val stream = ByteArrayOutputStream()
                outBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                outBitmap.recycle()
                result[key] = stream.toByteArray()
            } catch (_: Exception) {
            }
        }
        return result
    }

    private fun walletAliases(lower: String): List<String> = when {
        lower.contains("gotyme") || lower.contains("go tyme") -> listOf("gotyme", "gotyme bank", "go tyme")
        lower.contains("maribank") || lower.contains("mari bank") || lower.contains("seabank") -> listOf("maribank", "mari bank", "seabank")
        lower.contains("hellomoney") || lower.contains("hello money") || lower.contains("aub") -> listOf("hellomoney", "hello money", "aub")
        lower.contains("maya") || lower.contains("paymaya") -> listOf("maya", "paymaya")
        lower.contains("gcash") -> listOf("gcash")
        lower.contains("unionbank") || lower.contains("union bank") -> listOf("unionbank", "union bank")
        lower.contains("security bank") -> listOf("security bank", "securitybank")
        lower.contains("landbank") || lower.contains("land bank") -> listOf("landbank", "land bank")
        lower.contains("bpi") -> listOf("bpi", "bpi mobile")
        lower.contains("bdo") -> listOf("bdo", "bdo online", "bdo pay")
        lower.contains("metrobank") || lower.contains("metro") -> listOf("metrobank")
        lower.contains("rcbc") -> listOf("rcbc", "rcbc pulz")
        lower.contains("chinabank") -> listOf("chinabank", "china bank")
        lower.contains("eastwest") -> listOf("eastwest", "eastwest easyway")
        lower.contains("pnb") -> listOf("pnb", "pnb digital")
        lower.contains("grab") -> listOf("grab", "grabpay")
        lower.contains("shopee") -> listOf("shopee", "shopeepay")
        lower.contains("paypal") -> listOf("paypal")
        lower.contains("wise") -> listOf("wise")
        lower.contains("atome") -> listOf("atome")
        lower.contains("tonik") -> listOf("tonik")
        lower.contains("cimb") -> listOf("cimb", "cimb bank ph")
        else -> listOf(lower)
    }
}
