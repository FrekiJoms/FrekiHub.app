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
  static Future<void> scanSms() async {
    try {
      await NativeSession.channel.invokeMethod('smsScan');
    } catch (_) {}
  }

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
      'sms': data.prefs['smsScanning'] == 'true',
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

  static Future<void> _sanitizeCompoundMethods(
    AppDatabase db,
    Map<String, String> prefs,
  ) async {
    final compound = await (db.select(
      db.entries,
    )..where((e) => e.method.like('% + %'))).get();
    for (final row in compound) {
      final cleaned = _preferResolvedMethod(row.method, '', prefs);
      if (cleaned != row.method) {
        await (db.update(db.entries)..where((e) => e.id.equals(row.id)))
            .write(EntriesCompanion(method: Value(cleaned)));
      }
    }
  }

  static Future<bool> _reconcile(AppDatabase db) async {
    final prefs = await db.readPreferences();
    await _sanitizeCompoundMethods(db, prefs);
    if (prefs['smsScanning'] == 'true') {
      try {
        await scanSms();
      } catch (_) {}
    }
    final source =
        await NativeSession.channel.invokeMethod<String>('automationEvents') ??
        '[]';
    final events = (jsonDecode(source) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final acknowledged = <String>[];
    final pending = await NativeSession.pending();
    if (events.isEmpty && pending == null) {
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
    var cachedSample = int.tryParse(prefs['locationSampleTime'] ?? '') ?? 0;
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
          if (action == 'location_stay' && event['dwellMinutes'] is num) {
            await db.pref(
              'locationDwellMinutes',
              (event['dwellMinutes'] as num).toInt(),
            );
          } else if (action == 'location') {
            await db.pref('locationDwellMinutes', 0);
          }
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
              ? await (db.select(db.entries)..where(
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
            final currentSource = _resolvePurchaseMethod(event, prefs);
            final resolved = _preferResolvedMethod(
              duplicate.method,
              currentSource,
              prefs,
            );
            if (resolved != duplicate.method) {
              await (db.update(db.entries)
                    ..where((e) => e.id.equals(duplicate.id)))
                  .write(EntriesCompanion(method: Value(resolved)));
            }
            acknowledged.add(id);
            continue;
          }
          final resolvedMethod = _resolvePurchaseMethod(event, prefs);
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
                  method: resolvedMethod,
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
                'source': resolvedMethod,
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
        if (prefs['activityLogging'] == 'true') {
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
    final postData = await db.readAll();
    await deliverReceipts(db, postData.prefs);
    if (pending != null) {
      final pendingId = pending['id'] as String;
      final saved = postData.sessions
          .where((s) => s.id == pendingId)
          .firstOrNull;
      // Its queued clock-in can be in a later batch. Keep the end until committed.
      if (saved?.ended != null) await NativeSession.acknowledge();
    }
    if (acknowledged.isNotEmpty) {
      await NativeSession.channel.invokeMethod('automationAck', acknowledged);
    }
    await configure(postData);
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

  static List<String> _savedMethods(Map<String, String> prefs) {
    try {
      return List<String>.from(jsonDecode(prefs['methods'] ?? '[]') as List)
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _canonicalWalletMatch(
    String candidate,
    Map<String, String> prefs,
  ) {
    final lower = candidate.trim().toLowerCase();
    if (lower.isEmpty) return candidate.trim();
    for (final m in _savedMethods(prefs)) {
      if (m.toLowerCase() == lower) return m;
    }
    return candidate.trim();
  }

  static bool _isMessagingPackage(String pkg) =>
      pkg == 'sms' ||
      pkg == 'com.google.android.apps.messaging' ||
      pkg == 'com.samsung.android.messaging' ||
      pkg == 'com.android.mms' ||
      pkg == 'com.android.messaging' ||
      pkg.contains('.messaging') ||
      pkg.contains('.mms') ||
      pkg.contains('.sms');

  static bool _isGenericMethod(String value) {
    final lower = value.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'other' ||
        lower == 'messaging' ||
        lower == 'messages' ||
        lower == 'sms' ||
        lower == 'text messages' ||
        lower == 'mms' ||
        lower == 'automation';
  }

  static final RegExp _numericSender = RegExp(r'^[+0-9\s()-]{3,}$');

  static String _preferResolvedMethod(
    String existing,
    String incoming,
    Map<String, String> prefs,
  ) {
    final parts = existing
        .split(' + ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !_isGenericMethod(s))
        .toList();
    if (parts.isNotEmpty) return _canonicalWalletMatch(parts.first, prefs);
    if (!_isGenericMethod(incoming)) {
      return _canonicalWalletMatch(incoming, prefs);
    }
    return existing.trim().isEmpty ? 'Other' : existing.trim();
  }

  static String _resolvePurchaseMethod(
    Map<String, dynamic> event, [
    Map<String, String> prefs = const {},
  ]) {
    final raw = ((event['source'] ?? event['package']) as String? ?? '').trim();
    final pkg = (event['package'] as String? ?? '').trim().toLowerCase();
    if (pkg.isNotEmpty && !_isMessagingPackage(pkg)) {
      for (final entry in prefs.entries) {
        if (entry.key.startsWith('wallet:') &&
            entry.key.endsWith(':package') &&
            entry.value.trim().toLowerCase() == pkg) {
          final walletName = entry.key.substring(
            'wallet:'.length,
            entry.key.length - ':package'.length,
          );
          if (walletName.trim().isNotEmpty) {
            return _canonicalWalletMatch(walletName, prefs);
          }
        }
      }
    }
    final isMessaging =
        _isGenericMethod(raw) ||
        _numericSender.hasMatch(raw) ||
        (_isMessagingPackage(pkg) && _isGenericMethod(raw));
    if (!isMessaging) {
      for (final rule in _providerPatterns) {
        if (rule.pattern.hasMatch(raw)) {
          return _canonicalWalletMatch(rule.label, prefs);
        }
      }
      return _canonicalWalletMatch(raw, prefs);
    }
    final text = '${event['title'] ?? ''} ${event['merchant'] ?? ''} $raw';
    for (final saved in _savedMethods(prefs)) {
      if (_isGenericMethod(saved) ||
          saved.toLowerCase() == 'cash' ||
          saved.length < 2) {
        continue;
      }
      if (RegExp(
        '\\b${RegExp.escape(saved)}\\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        return saved;
      }
    }
    for (final rule in _providerPatterns) {
      if (rule.pattern.hasMatch(text)) {
        return _canonicalWalletMatch(rule.label, prefs);
      }
    }
    return 'Other';
  }

  static final List<({String label, RegExp pattern})> _providerPatterns = [
    (
      label: 'Maya',
      pattern: RegExp(r'\b(?:maya|paymaya)\b', caseSensitive: false),
    ),
    (label: 'GCash', pattern: RegExp(r'\bgcash\b', caseSensitive: false)),
    (
      label: 'MariBank',
      pattern: RegExp(
        r'\b(?:maribank|mari\s+bank|seabank|sea\s+bank)\b',
        caseSensitive: false,
      ),
    ),
    (
      label: 'GoTyme',
      pattern: RegExp(r'\b(?:gotyme|go\s+tyme)\b', caseSensitive: false),
    ),
    (
      label: 'HelloMoney',
      pattern: RegExp(
        r'\b(?:hellomoney|hello\s+money)\b',
        caseSensitive: false,
      ),
    ),
    (label: 'BPI', pattern: RegExp(r'\bbpi\b', caseSensitive: false)),
    (
      label: 'Metrobank',
      pattern: RegExp(r'\bmetrobank\b', caseSensitive: false),
    ),
    (label: 'BDO', pattern: RegExp(r'\bbdo\b', caseSensitive: false)),
    (
      label: 'UnionBank',
      pattern: RegExp(r'\b(?:unionbank|union\s+bank)\b', caseSensitive: false),
    ),
    (
      label: 'LandBank',
      pattern: RegExp(r'\b(?:landbank|land\s+bank)\b', caseSensitive: false),
    ),
    (label: 'RCBC', pattern: RegExp(r'\brcbc\b', caseSensitive: false)),
    (
      label: 'Security Bank',
      pattern: RegExp(r'\bsecurity\s+bank\b', caseSensitive: false),
    ),
    (label: 'PNB', pattern: RegExp(r'\bpnb\b', caseSensitive: false)),
    (
      label: 'Chinabank',
      pattern: RegExp(r'\bchinabank\b', caseSensitive: false),
    ),
    (label: 'EastWest', pattern: RegExp(r'\beastwest\b', caseSensitive: false)),
    (label: 'PayPal', pattern: RegExp(r'\bpaypal\b', caseSensitive: false)),
    (label: 'GrabPay', pattern: RegExp(r'\bgrabpay\b', caseSensitive: false)),
    (
      label: 'ShopeePay',
      pattern: RegExp(r'\bshopeepay\b', caseSensitive: false),
    ),
  ];
}
