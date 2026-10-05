package com.frekihub.freki_hub

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Durable per-event preferences, with bounded transport and explicit sample backpressure. */
object RuntimeEvents {
    const val BATCH_SIZE = 200
    private const val SAMPLE_BACKPRESSURE = 5000L
    private fun prefs(c: Context) = c.getSharedPreferences("runtime_events", Context.MODE_PRIVATE)
    private fun segment(c: Context, sequence: Long) = c.getSharedPreferences("runtime_events_${sequence / BATCH_SIZE}", Context.MODE_PRIVATE)
    private fun key(sequence: Long) = "event:$sequence"
    @Synchronized private fun migrate(c: Context) {
        val store = prefs(c)
        val legacy = Automation.prefs(c)
        if (store.getBoolean("migrated", false)) {
            // Retry legacy cleanup if the process ended after the migration commit.
            if (legacy.contains("events")) check(legacy.edit().remove("events").commit())
            return
        }
        val events = JSONArray(legacy.getString("events", "[]"))
        val edit = store.edit()
        for (start in 0 until events.length() step BATCH_SIZE) {
            val chunk = segment(c, start.toLong()).edit()
            for (i in start until minOf(events.length(), start + BATCH_SIZE)) chunk.putString(key(i.toLong()), events.getJSONObject(i).toString())
            check(chunk.commit()) { "Could not migrate pending event segment" }
        }
        check(edit.putLong("head", 0).putLong("tail", events.length().toLong()).putBoolean("migrated", true).commit()) { "Could not migrate pending events" }
        // The new queue is durable before removing the replayable legacy source.
        check(legacy.edit().remove("events").commit()) { "Could not acknowledge queue migration" }
    }
    @Synchronized fun pending(c: Context): Long {
        migrate(c)
        val store = prefs(c)
        return recoverTail(c) - store.getLong("head", 0)
    }
    private fun recoverTail(c: Context): Long {
        val store = prefs(c)
        var tail = store.getLong("tail", 0)
        // A crash after the event commit but before the index commit is replayable.
        while (segment(c, tail).contains(key(tail))) tail++
        if (tail != store.getLong("tail", 0)) check(store.edit().putLong("tail", tail).commit())
        return tail
    }
    @Synchronized fun samplesPaused(c: Context) = pending(c) >= SAMPLE_BACKPRESSURE
    @Synchronized fun emit(c: Context, event: JSONObject) {
        migrate(c)
        val store = prefs(c)
        val tail = recoverTail(c)
        if (!event.has("id")) event.put("id", UUID.randomUUID().toString())
        check(segment(c, tail).edit().putString(key(tail), event.toString()).commit()) { "Could not queue runtime event" }
        check(store.edit().putLong("tail", tail + 1).commit()) { "Could not index runtime event" }
    }
    @Synchronized fun read(c: Context): String {
        migrate(c)
        val store = prefs(c)
        val head = store.getLong("head", 0)
        val tail = recoverTail(c)
        val result = JSONArray()
        for (sequence in head until minOf(tail, head + BATCH_SIZE)) {
            result.put(JSONObject(checkNotNull(segment(c, sequence).getString(key(sequence), null))))
        }
        return result.toString()
    }
    @Synchronized fun acknowledge(c: Context, ids: List<String>) {
        migrate(c)
        val store = prefs(c)
        var head = store.getLong("head", 0)
        val tail = recoverTail(c)
        val acknowledged = ids.toHashSet()
        // Import acknowledges a committed prefix. Preserve any unacknowledged event.
        while (head < tail) {
            val event = JSONObject(checkNotNull(segment(c, head).getString(key(head), null)))
            if (event.getString("id") !in acknowledged) break
            head++
        }
        check(store.edit().putLong("head", head).commit()) { "Could not acknowledge runtime events" }
        cleanup(c)
    }
    private fun cleanup(c: Context) {
        val store = prefs(c)
        var cleaned = store.getLong("cleanedSegment", 0)
        val complete = store.getLong("head", 0) / BATCH_SIZE
        while (cleaned < complete) {
            check(c.deleteSharedPreferences("runtime_events_$cleaned")) { "Could not reclaim acknowledged event segment" }
            cleaned++
            check(store.edit().putLong("cleanedSegment", cleaned).commit())
        }
    }
    @Synchronized fun reset(c: Context) {
        val tail = prefs(c).getLong("tail", 0)
        for (part in 0..(tail / BATCH_SIZE)) c.deleteSharedPreferences("runtime_events_$part")
        check(prefs(c).edit().clear().putBoolean("migrated", true).commit())
    }
}
