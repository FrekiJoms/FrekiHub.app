package com.frekihub.freki_hub

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.provider.Settings

object NotificationSoundSettings {
    private val channels = mapOf(
        "reminders" to Pair("frekihub_rule_reminders", "Rule reminders"),
        "transactions" to Pair("frekihub_transactions", "Saved transactions"),
        "sessions" to Pair("frekihub_timer", "Running session")
    )

    fun open(c: Context, category: String) {
        val (id, name) = channels[category] ?: throw IllegalArgumentException("Unknown notification category")
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            val manager = c.getSystemService(NotificationManager::class.java)
            // Create only missing channels; never overwrite a sound chosen in Android settings.
            if (manager.getNotificationChannel(id) == null) {
                val quiet = category == "sessions"
                manager.createNotificationChannel(NotificationChannel(id, name,
                    if (quiet) NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT).apply {
                    if (quiet) { setSound(null, null); enableVibration(false) }
                })
            }
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, c.packageName).putExtra(Settings.EXTRA_CHANNEL_ID, id)
                .apply {
                    if (Build.VERSION.SDK_INT >= 31) putExtra(Settings.EXTRA_CHANNEL_FILTER_LIST, arrayOf(NotificationChannel.EDIT_SOUND))
                }
        } else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, c.packageName)
        try { c.startActivity(intent) }
        catch (_: android.content.ActivityNotFoundException) {
            c.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${c.packageName}")))
        }
    }

    fun sound(c: Context, category: String): String {
        val id = channels[category]?.first ?: return "silent"
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = c.getSystemService(NotificationManager::class.java).getNotificationChannel(id)
            if (channel != null) {
                if (channel.importance < NotificationManager.IMPORTANCE_DEFAULT) return "silent"
                return channel.sound?.toString() ?: "silent"
            }
        }
        return if (category == "sessions") "silent" else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION).toString()
    }
}
