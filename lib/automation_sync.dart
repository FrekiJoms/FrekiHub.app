import 'dart:convert';

import 'package:drift/drift.dart';

import 'data.dart';
import 'services.dart';

abstract final class AutomationSync {
  static Future<void>? _work;
  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(
        await NativeSession.channel.invokeMapMethod<String, dynamic>(
              'automationStatus',
            ) ??
            {},
      );
  static Map<String, dynamic> config(AppData data) {
    Map<String, dynamic> stored = {};
    try {
      stored = Map<String, dynamic>.from(
        jsonDecode(data.prefs['automation'] ?? '{}'),
      );
    } catch (_) {}
    return {
      ...stored,
      'logging': data.prefs['activityLogging'] == 'true',
      'locationEnabled': data.prefs['locationEnabled'] == 'true',
      'purchases': data.prefs['purchaseScanning'] == 'true',
    };
  }

  static Future<void> configure(AppData data) => NativeSession.channel
      .invokeMethod('automationConfig', jsonEncode(config(data)));
  static Future<void> reconcile(AppDatabase db) =>
      _work ??= _reconcile(db).whenComplete(() => _work = null);
  static Future<void> _reconcile(AppDatabase db) async {
    final source =
        await NativeSession.channel.invokeMethod<String>('automationEvents') ??
        '[]';
    final events = (jsonDecode(source) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final acknowledged = <String>[];
    final data = await db.readAll();
    final pending = await NativeSession.pending();
    await db.transaction(() async {
      if (pending != null) {
        await db.clockOut(pending['id'] as String, at: pending['ended'] as int);
      }
      for (final event in events) {
        final id = event['id'] as String;
        final action = event['action'];
        final time = DateTime.fromMillisecondsSinceEpoch(event['time'] as int);
        if (event['lat'] != null && event['location'] != null) {
          await db.pref('locationName', event['location']);
          await db.pref('locationDetails', jsonEncode(event));
          await db.pref(
            'locationSampleTime',
            event['locationTime'] ?? event['time'],
          );
        }
        if (action == 'auto_clock_in') {
          final sessionId = event['sessionId'] as String;
          final exists = await (db.select(
            db.sessions,
          )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
          final running = await (db.select(
            db.sessions,
          )..where((s) => s.ended.isNull())).getSingleOrNull();
          if (exists == null && running == null) {
            await db
                .into(db.sessions)
                .insert(
                  Session(
                    id: sessionId,
                    day: dayKey(time),
                    kind: event['kind'] as String? ?? 'OJT',
                    started: event['started'] as int,
                    ended: null,
                    note: 'Automatic · ${event['location']}',
                  ),
                );
          }
        } else if (action == 'auto_clock_out') {
          await db.clockOut(
            event['sessionId'] as String,
            at: event['time'] as int,
          );
        } else if (action == 'purchase') {
          int amount;
          try {
            amount = parseMoney(
              event['amount'] as String,
              event['currency'] as String,
            );
          } on FormatException {
            acknowledged.add(id);
            continue;
          }
          if (amount <= 0) {
            acknowledged.add(id);
            continue;
          }
          await db
              .into(db.entries)
              .insert(
                Entry(
                  id: id,
                  day: dayKey(time),
                  kind: 'expense',
                  amount: amount,
                  currency: event['currency'] as String,
                  category: 'Other',
                  method: (event['source'] ?? event['package']) as String,
                  note: event['merchant'] as String,
                  occurrence: id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
          // Replace the generic insert log with the notification's precise timestamp and snapshot.
          await db.customStatement('DELETE FROM activity_logs WHERE id = ?', [
            'transaction:$id',
          ]);
        }
        if (action == 'auto_clock_in' &&
            pending != null &&
            event['sessionId'] == pending['id']) {
          await db.clockOut(
            pending['id'] as String,
            at: pending['ended'] as int,
          );
        }
        if (data.prefs['activityLogging'] == 'true') {
          if (action == 'auto_clock_in') {
            await db.customStatement('DELETE FROM activity_logs WHERE id = ?', [
              'session_start:${event['sessionId']}',
            ]);
          }
          if (action == 'auto_clock_out') {
            await db.customStatement('DELETE FROM activity_logs WHERE id = ?', [
              'session_end:${event['sessionId']}',
            ]);
          }
          await db.addActivity(event);
        }
        if (action == 'location') {
          await db.pref(
            'locationName',
            event['location'] ?? 'Location unavailable',
          );
          await db.pref('locationDetails', jsonEncode(event));
        }
        acknowledged.add(id);
      }
    });
    if (pending != null) await NativeSession.acknowledge();
    if (acknowledged.isNotEmpty) {
      await NativeSession.channel.invokeMethod('automationAck', acknowledged);
    }
    await configure(await db.readAll());
  }
}
