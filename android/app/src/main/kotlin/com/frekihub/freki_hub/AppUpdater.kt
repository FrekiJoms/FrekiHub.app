package com.frekihub.freki_hub

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

object AppUpdater {
    @Volatile
    var channel: MethodChannel? = null

    private val installing = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun packageInfo(context: Context): Map<String, Any> {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "versionName" to (info.versionName ?: "1.0.0"),
            "versionCode" to info.longVersionCode
        )
    }

    fun canInstall(context: Context): Boolean =
        context.packageManager.canRequestPackageInstalls()

    fun openInstallSettings(context: Context) {
        val intent = Intent(
            android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun downloadAndInstall(context: Context, url: String) {
        if (!url.startsWith("https://")) {
            throw IllegalArgumentException("Update download requires an HTTPS URL.")
        }
        if (!canInstall(context)) {
            throw SecurityException("Allow app installs from this source first.")
        }
        if (!installing.compareAndSet(false, true)) {
            throw IllegalStateException("An update download is already in progress.")
        }
        val appContext = context.applicationContext
        Thread {
            var connection: HttpURLConnection? = null
            var session: PackageInstaller.Session? = null
            try {
                connection = openHttpsFollowingRedirects(url)
                val code = connection.responseCode
                if (code !in 200..299) {
                    throw IllegalStateException("Server returned HTTP $code.")
                }
                val total = connection.contentLengthLong
                val installer = appContext.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                ).apply {
                    if (total > 0) setSize(total)
                }
                val sessionId = installer.createSession(params)
                session = installer.openSession(sessionId)

                connection.inputStream.use { input: InputStream ->
                    session.openWrite(
                        "app_update.apk",
                        0,
                        if (total > 0) total else -1L
                    ).use { out ->
                        val buffer = ByteArray(64 * 1024)
                        var downloaded = 0L
                        var lastNotify = 0L
                        while (true) {
                            val read = input.read(buffer)
                            if (read == -1) break
                            out.write(buffer, 0, read)
                            downloaded += read
                            val now = System.currentTimeMillis()
                            if (now - lastNotify >= 100L) {
                                lastNotify = now
                                val progress = if (total > 0) {
                                    (downloaded.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
                                } else null
                                postProgress(downloaded, total, progress)
                            }
                        }
                        postProgress(downloaded, total, if (total > 0) 1.0 else null)
                        session.fsync(out)
                    }
                }
                connection.disconnect()
                connection = null

                val callbackIntent = Intent(appContext, UpdateInstallReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    appContext,
                    93,
                    callbackIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                session.commit(pendingIntent.intentSender)
                session.close()
                session = null
                postStatus("committing", null)
            } catch (error: Exception) {
                try {
                    session?.abandon()
                } catch (_: Exception) {
                }
                postStatus("failed", error.message ?: "Could not download update.")
            } finally {
                try {
                    connection?.disconnect()
                } catch (_: Exception) {
                }
                installing.set(false)
            }
        }.start()
    }

    private fun openHttpsFollowingRedirects(startUrl: String): HttpURLConnection {
        var current = startUrl
        repeat(6) {
            val parsed = URL(current)
            if (parsed.protocol != "https") {
                throw IllegalArgumentException("Update redirect must remain HTTPS.")
            }
            val conn = (parsed.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "FrekiAppUpdater")
            }
            val code = conn.responseCode
            if (code in listOf(301, 302, 303, 307, 308)) {
                val next = conn.getHeaderField("Location")
                conn.disconnect()
                if (next.isNullOrBlank()) {
                    throw IllegalStateException("Empty redirect location.")
                }
                current = URL(parsed, next).toString()
            } else {
                return conn
            }
        }
        throw IllegalStateException("Too many redirects while downloading update.")
    }

    private fun postProgress(received: Long, total: Long, progress: Double?) {
        mainHandler.post {
            channel?.invokeMethod(
                "updateProgress",
                mapOf(
                    "received" to received,
                    "total" to total,
                    "progress" to progress
                )
            )
        }
    }

    internal fun postStatus(status: String, message: String?) {
        mainHandler.post {
            channel?.invokeMethod(
                "updateStatus",
                mapOf(
                    "status" to status,
                    "message" to message
                )
            )
        }
    }
}

class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmIntent)
                    AppUpdater.postStatus("confirming", null)
                } else {
                    AppUpdater.postStatus("failed", "Installer confirmation unavailable.")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> AppUpdater.postStatus("installed", null)
            PackageInstaller.STATUS_FAILURE_ABORTED -> AppUpdater.postStatus("cancelled", null)
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                AppUpdater.postStatus("failed", message ?: "Update was not installed.")
            }
        }
    }
}
