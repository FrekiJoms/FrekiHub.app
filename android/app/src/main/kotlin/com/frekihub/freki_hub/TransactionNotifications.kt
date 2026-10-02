package com.frekihub.freki_hub

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object TransactionNotifications {
    private const val CHANNEL = "frekihub_transactions"

    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun post(context: Context, receipt: Map<*, *>): Boolean {
        if (!allowed(context)) return false
        val id = receipt["id"] as? String ?: return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Saved transactions", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Confirmation after detected purchases are saved to Budget"
        })
        val open = PendingIntent.getActivity(context, 92,
            Intent(context, MainActivity::class.java).putExtra("openPage", "budget").addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun builder() = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        val details = buildString {
            append("Added to Budget and saved\n")
            append("Amount: ${receipt["amount"]}\n")
            append("Merchant / item: ${receipt["merchant"]}\n")
            append("Date: ${receipt["date"]}\n")
            append("Payment app: ${receipt["source"]}\n")
            append("Location: ${receipt["location"]}")
            val reference = receipt["reference"] as? String
            if (!reference.isNullOrBlank()) append("\nReference: $reference")
        }
        val publicVersion = builder().setSmallIcon(R.drawable.ic_transaction)
            .setContentTitle("Transaction saved").setContentText("Added to your FrekiHub Budget").build()
        val notification = builder().setSmallIcon(R.drawable.ic_transaction)
            .setContentTitle(receipt["title"] as? String ?: "Transaction saved")
            .setContentText("${receipt["amount"]} · ${receipt["merchant"]}")
            .setSubText("Budget · Expense")
            .setStyle(Notification.BigTextStyle().bigText(details))
            .setWhen((receipt["time"] as? Number)?.toLong() ?: System.currentTimeMillis())
            .setShowWhen(true).setAutoCancel(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(publicVersion)
            .setCategory(Notification.CATEGORY_STATUS).setContentIntent(open).build()
        manager.notify(id, 92, notification)
        return true
    }
}
