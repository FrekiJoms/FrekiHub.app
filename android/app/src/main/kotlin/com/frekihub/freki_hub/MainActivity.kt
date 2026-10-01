package com.frekihub.freki_hub

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var startData: Map<*, *>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frekihub/session").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("session", MODE_PRIVATE)
            when (call.method) {
                "start" -> {
                    val data = call.arguments as Map<*, *>
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        startData = data; pendingResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 73)
                    } else { startTimer(data); result.success(true) }
                }
                "stop" -> { stopService(Intent(this, SessionService::class.java)); prefs.edit().remove("id").commit(); result.success(null) }
                "pending" -> { val id = prefs.getString("pendingId", null); result.success(if (id == null) null else mapOf("id" to id, "ended" to prefs.getLong("pendingEnd", 0))) }
                "acknowledge" -> { prefs.edit().remove("pendingId").remove("pendingEnd").commit(); result.success(null) }
                else -> result.notImplemented()
            }
        }
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
    }
}
