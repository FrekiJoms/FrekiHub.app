package com.frekihub.freki_hub

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Bounded foreground-only lookup; does not log or evaluate automation rules. */
object MapLocation {
    private fun fresh(location: Location?): Boolean {
        if (location == null || !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0) return false
        val age = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
        val wallAge = System.currentTimeMillis() - location.time
        return age in 0..120_000_000_000L && wallAge in -1000L..120000L &&
            location.latitude.isFinite() && location.longitude.isFinite() &&
            location.latitude in -90.0..90.0 && location.longitude in -180.0..180.0
    }

    /** One cached sample at an action instant; never starts historical tracking. */
    @SuppressLint("MissingPermission")
    fun cached(context: Context, at: Long): Location? {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return null
        val manager = context.getSystemService(LocationManager::class.java)
        if (!manager.isLocationEnabled) return null
        return manager.getProviders(true)
            .filter { it in setOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.FUSED_PROVIDER) }
            .mapNotNull { provider -> try { manager.getLastKnownLocation(provider) } catch (_: Exception) { null } }
            .filter { fresh(it) && at - it.time in -1000L..120000L && it.accuracy <= 100 }
            .minByOrNull { it.accuracy }
    }

    @SuppressLint("MissingPermission")
    fun request(context: Context, done: (Location?, String?) -> Unit) {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            done(null, "Allow precise location to find yourself on the map."); return
        }
        val manager = context.getSystemService(LocationManager::class.java)
        if (!manager.isLocationEnabled) { done(null, "Turn on your phone's Location setting, then try again."); return }
        val providers = manager.getProviders(true).filter { it in setOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.FUSED_PROVIDER) }
        if (providers.isEmpty()) { done(null, "No location provider is available. Turn on Location and try again."); return }
        var best: Location? = null
        fun consider(location: Location?) {
            if (fresh(location) && (best == null || !fresh(best) || location!!.accuracy < best!!.accuracy)) best = location
        }
        for (provider in providers) {
            try { consider(manager.getLastKnownLocation(provider)) } catch (_: Exception) { /* Try other providers. */ }
        }
        if (fresh(best) && best!!.accuracy <= 100) { done(best, null); return }
        val handler = Handler(Looper.getMainLooper())
        val signals = mutableListOf<CancellationSignal>()
        var finished = false
        var remaining = providers.size
        lateinit var timeout: Runnable
        fun finish() {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            signals.forEach { it.cancel() }
            val fix = best?.takeIf { fresh(it) }
            done(fix, if (fix == null) "No fresh location fix yet. Try again near a window or outdoors." else null)
        }
        timeout = Runnable { finish() }
        handler.postDelayed(timeout, 20_000)
        for (provider in providers) {
            if (finished) break
            val signal = CancellationSignal()
            signals.add(signal)
            try {
                manager.getCurrentLocation(provider, signal, context.mainExecutor) { location ->
                    if (!finished) {
                        consider(location)
                        remaining--
                        if ((fresh(best) && best!!.accuracy <= 100) || remaining == 0) finish()
                    }
                }
            } catch (_: Exception) {
                remaining--
                if (remaining == 0) finish()
            }
        }
    }
}
