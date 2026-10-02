package com.frekihub.freki_hub

import android.Manifest
import android.content.Intent
import android.content.ComponentName
import android.app.NotificationManager
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import android.os.Build
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val readySounds = mutableSetOf<Int>()
    private var pendingResult: MethodChannel.Result? = null
    private var startData: Map<*, *>? = null
    private var locationResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frekihub/session").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("session", MODE_PRIVATE)
            when (call.method) {
                "automationConfig" -> { Automation.configure(this, call.arguments as String); result.success(null) }
                "automationReset" -> { Automation.prefs(this).edit().clear().commit(); Automation.configure(this, "{}"); result.success(null) }
                "automationEvents" -> result.success(Automation.prefs(this).getString("events", "[]"))
                "automationAck" -> { Automation.acknowledge(this, (call.arguments as List<*>).filterIsInstance<String>()); result.success(null) }
                "automationStatus" -> result.success(mapOf("location" to (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED), "background" to Automation.allowed(this), "notifications" to if (Build.VERSION.SDK_INT >= 27) getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(ComponentName(this, PurchaseListener::class.java)) else Settings.Secure.getString(contentResolver, "enabled_notification_listeners").orEmpty().contains(packageName)))
                "locationPermission" -> {
                    if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (locationResult != null) result.error("busy", "A permission request is already open", null)
                    else { locationResult = result; requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 74) }
                }
                "backgroundPermission" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                "notificationPermission" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                "currentLocation" -> Automation.requestLocation(this) { location -> if (location == null) result.error("location", "No fresh location available. Enable precise location and try again.", null) else result.success(Automation.locationJson(this, location).toString()) }
                "notificationApps" -> {
                    val apps = packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0).distinctBy { it.activityInfo.packageName }.map { mapOf("name" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName) }.sortedBy { it["name"] }
                    result.success(apps)
                }
                "sound" -> {
                    try { playSound(call.arguments as? String); result.success(null) }
                    catch (e: Exception) { result.error("sound", e.message, null) }
                }
                "start" -> {
                    val data = call.arguments as Map<*, *>
                    if (prefs.getString("pendingId", null) != data["id"]) prefs.edit().putString("id", data["id"] as String).putLong("started", (data["started"] as Number).toLong()).commit()
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        startData = data; pendingResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 73)
                    } else { startTimer(data); result.success(true) }
                }
                "stop" -> { stopService(Intent(this, SessionService::class.java)); prefs.edit().remove("id").commit(); Automation.prefs(this).edit().remove("activeRule").commit(); result.success(null) }
                "pending" -> { val id = prefs.getString("pendingId", null); result.success(if (id == null) null else mapOf("id" to id, "ended" to prefs.getLong("pendingEnd", 0))) }
                "acknowledge" -> { prefs.edit().remove("pendingId").remove("pendingEnd").commit(); result.success(null) }
                else -> result.notImplemented()
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
            assets.openFd(asset).use { soundIds[name!!] = pool.load(it, 1) }
        }
    }
    override fun onDestroy() {
        soundPool?.release(); soundPool = null; soundIds.clear(); readySounds.clear()
        super.onDestroy()
    }
    private fun startTimer(data: Map<*, *>) {
        val id = data["id"] as String
        if (getSharedPreferences("session", MODE_PRIVATE).getString("pendingId", null) == id) return
        val intent = Intent(this, SessionService::class.java).putExtra("id", id).putExtra("started", (data["started"] as Number).toLong()).putExtra("day", data["day"] as String)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 73) {
            val approved = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (approved) startData?.let { startTimer(it) }
            pendingResult?.success(approved); pendingResult = null; startData = null
        }
        if (requestCode == 74) { locationResult?.success(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED); locationResult = null }
    }
}
