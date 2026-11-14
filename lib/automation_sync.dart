import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import 'data.dart';
import 'services.dart';
import 'rule_language.dart';
import 'map_records.dart';

import 'package:flutter/widgets.dart';

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
    stored.remove('snapshot');
    for (final rule in stored['rules'] as List? ?? []) {
      if (rule['source'] is String) {
        try {
          rule['program'] = RuleCompiler.compile(rule['source'] as String);
        } on FormatException {
          rule['enabled'] = false;
        }
      } else if (rule['program'] != null) {
        rule['enabled'] = false;
      }
    }
    return {
      ...stored,
      'knownTargets': RuleCatalog.targets,
      'logging': data.prefs['activityLogging'] == 'true',
      'locationEnabled': data.prefs['locationEnabled'] == 'true',
      'purchases': data.prefs['purchaseScanning'] == 'true',
    };
  }

  static Future<void> configure(AppData data) =>
      NativeSession.channel.invokeMethod(
        'automationConfig',
        jsonEncode({
          ...config(data),
          'snapshot': RuleCatalog.snapshot(data)
            ..['app.foreground'] =
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed,
        }),
      );
  static Future<void> reconcile(AppDatabase db) =>
      _work ??= _drain(db).whenComplete(() => _work = null);
  static Future<void> _drain(AppDatabase db) async {
    while (await _reconcile(db)) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  static Future<bool> _reconcile(AppDatabase db) async {
    final source =
        await NativeSession.channel.invokeMethod<String>('automationEvents') ??
        '[]';
    final events = (jsonDecode(source) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final acknowledged = <String>[];
    final pending = await NativeSession.pending();
    if (events.isEmpty && pending == null) {
      final prefs = await db.readPreferences();
      await deliverReceipts(db, prefs);
      final stored = config(AppData([], [], [], prefs));
      if ((stored['rules'] as List? ?? []).any(
        (r) => r['source'] != null && r['enabled'] == true,
      )) {
        await configure(await db.readAll());
      } else {
        await configure(AppData([], [], [], prefs));
      }
      return false;
    }
    final data = await db.readAll();
    var cachedSample =
        int.tryParse(data.prefs['locationSampleTime'] ?? '') ?? 0;
    await db.transaction(() async {
      if (pending != null) {
        await NativeSession.applyPending(db, pending);
      }
      for (final event in events) {
        final id = event['id'] as String;
        final action = event['action'];
        final time = DateTime.fromMillisecondsSinceEpoch(event['time'] as int);
        final fix = MapUserLocation.parse(event, DateTime.now());
        if (fix != null &&
            fix.sampled >= cachedSample &&
            event['location'] != null) {
          cachedSample = fix.sampled;
          await db.pref('locationName', event['location']);
          await db.pref('locationDetails', jsonEncode(event));
          await db.pref('locationSampleTime', fix.sampled);
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
        } else if (action == 'rule_setting') {
          final key = event['key'];
          final value = event['value'];
          if (key == 'sound' && ['true', 'false'].contains(value) ||
              key == 'theme' && ['light', 'dark', 'system'].contains(value)) {
            await db.pref(key as String, value);
          }
        } else if (action == 'rule_toast') {
          await db.pref('ruleToast:$id', event['title']);
        } else if (action == 'purchase') {
          final kind = event['kind'] as String? ?? 'expense';
          if (kind != 'expense' && kind != 'income') {
            acknowledged.add(id);
            continue;
          }
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
          final existing =
              await (db.select(db.entries)
                    ..where((e) => e.id.equals(id) | e.occurrence.equals(id)))
                  .getSingleOrNull();
          final duplicate = existing == null
              ? await (db.select(db.entries)
                    ..where(
                      (e) =>
                          e.kind.equals(kind) &
                          e.amount.equals(amount) &
                          e.currency.equals(event['currency'] as String) &
                          e.note.equals(event['merchant'] as String) &
                          e.day.equals(dayKey(time)),
                    ))
                  .getSingleOrNull()
              : null;
          if (duplicate != null) {
            final currentSource =
                (event['source'] ?? event['package']) as String;
            final sources = <String>{
              ...duplicate.method.split(' + '),
              currentSource,
            }.where((s) => s.trim().isNotEmpty).toList();
            await (db.update(db.entries)
                  ..where((e) => e.id.equals(duplicate.id)))
                .write(EntriesCompanion(method: Value(sources.join(' + '))));
            acknowledged.add(id);
            continue;
          }
          await db
              .into(db.entries)
              .insert(
                Entry(
                  id: id,
                  day: dayKey(time),
                  kind: kind,
                  amount: amount,
                  currency: event['currency'] as String,
                  category: event['category'] as String? ?? 'Other',
                  method: (event['source'] ?? event['package']) as String,
                  note: event['merchant'] as String,
                  occurrence: id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
          if (existing == null) {
            final merchant = event['merchant'] as String;
            await db.pref(
              'purchaseNotice:$id',
              jsonEncode({
                'id': id,
                'title': 'Transaction saved',
                'kind': kind,
                'amount': money(amount, event['currency'] as String),
                'merchant': merchant,
                'time': event['time'],
                'date': DateFormat('d MMM y · h:mm a').format(time),
                'source': event['source'] ?? event['package'],
                'location': event['location'] ?? 'Location unavailable',
                'reference': event['reference'] ?? '',
              }),
            );
          }
          // Replace the generic insert log with the notification's precise timestamp and snapshot.
          await db.customStatement('DELETE FROM activity_logs WHERE id = ?', [
            'transaction:$id',
          ]);
        }
        if (action == 'auto_clock_in' &&
            pending != null &&
            event['sessionId'] == pending['id']) {
          await NativeSession.applyPending(db, pending);
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
        acknowledged.add(id);
      }
    });
    await deliverReceipts(db, await db.readPreferences());
    if (pending != null) {
      final saved = await (db.select(
        db.sessions,
      )..where((s) => s.id.equals(pending['id'] as String))).getSingleOrNull();
      // Its queued clock-in can be in a later batch. Keep the end until committed.
      if (saved?.ended != null) await NativeSession.acknowledge();
    }
    if (acknowledged.isNotEmpty) {
      await NativeSession.channel.invokeMethod('automationAck', acknowledged);
    }
    await configure(await db.readAll());
    return events.length >= 200;
  }

  static Future<void> deliverReceipts(
    AppDatabase db,
    Map<String, String> prefs,
  ) async {
    for (final pending in prefs.entries.where(
      (p) => p.key.startsWith('purchaseNotice:'),
    )) {
      try {
        final posted = await NativeSession.channel.invokeMethod<bool>(
          'transactionSaved',
          jsonDecode(pending.value),
        );
        if (posted == true) {
          await (db.delete(
            db.preferences,
          )..where((p) => p.key.equals(pending.key))).go();
        }
      } catch (_) {
        // A saved transaction stays saved even if Android cannot show its receipt.
        // Keep the receipt for the next foreground reconciliation.
      }
    }
  }
}
