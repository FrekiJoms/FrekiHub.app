package com.frekihub.freki_hub

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.os.Build
import android.content.pm.ServiceInfo
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences("session", MODE_PRIVATE)
        if (intent?.action == "clockOut") {
            val id = prefs.getString("id", null)
            if (id != null) prefs.edit().putString("pendingId", id).putLong("pendingEnd", System.currentTimeMillis()).remove("id").commit()
            stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY
        }
        val id = intent?.getStringExtra("id") ?: prefs.getString("id", null) ?: return START_NOT_STICKY
        val started = intent?.getLongExtra("started", 0) ?: prefs.getLong("started", 0)
        if (started <= 0 || prefs.getString("pendingId", null) == id) { stopSelf(); return START_NOT_STICKY }
        prefs.edit().putString("id", id).putLong("started", started).commit()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("frekihub_timer", "Running session", NotificationManager.IMPORTANCE_LOW).apply { description = "A quiet timer for your OJT session"; setSound(null, null); enableVibration(false) })
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, SessionService::class.java).setAction("clockOut"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "frekihub_timer") else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.ic_session).setContentTitle("FrekiHub · OJT in progress").setContentText("Clocked in at ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(started))}").setWhen(started).setUsesChronometer(true).setChronometerCountDown(false).setOngoing(true).setOnlyAlertOnce(true).setShowWhen(true).setContentIntent(open).addAction(Notification.Action.Builder(null, "Clock out", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(73, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(73, notification)
        return START_STICKY
    }
}
