import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/automation_sync.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/map_records.dart';
import 'package:freki_hub/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.readAll();
  });
  tearDown(() => db.close());
  Entry income(int amount) => Entry(
    id: 'income',
    day: '2026-10-05',
    kind: 'income',
    amount: amount,
    currency: 'PHP',
    category: 'Salary',
    method: 'Cash',
    note: '',
    occurrence: null,
  );
  Rule rule({int quantity = 1, int rate = 10000}) => Rule(
    id: 'rule',
    title: 'Planned expense',
    kind: 'expense',
    amount: rate,
    currency: 'PHP',
    quantity: quantity,
    basis: 'income',
    cadence: 'once',
    start: '2026-10-05',
    finish: null,
    category: 'Other',
    method: 'Cash',
    position: 0,
  );
  final day = DateTime(2026, 10, 5);

  test(
    'Large monthly bases cannot wrap into a recordable percentage amount',
    () {
      final entries = List.generate(
        2050,
        (i) => income(maxMoneyMinor).copyWith(id: 'income-$i'),
      );
      final occurrence = project(
        AppData([], entries, [rule()], {}),
        day,
        day,
      ).single;
      expect(occurrence.error, isNotNull);
      expect(occurrence.status, 'invalid');
    },
  );

  test('A backup above the former 20 MiB UI limit round-trips under the shared policy', () async {
    final chunk = List.filled(1024, 'x').join();
    final buffer = StringBuffer();
    for (var i = 0; i < 21 * 1024; i++) {
      buffer.write(chunk);
    }
    await db.pref('syntheticHistory', buffer.toString());
    final backup = await db.backup();
    expect(utf8.encode(backup).length, greaterThan(20 * 1024 * 1024));
    expect(utf8.encode(backup).length, lessThan(maxBackupBytes));
    await db.restore(backup);
    expect(
      (await db.readPreferences())['syntheticHistory']!.length,
      21 * 1024 * 1024,
    );
  });

  test(
    'Percentage overflow cannot be recorded and remains exportable',
    () async {
      await db.into(db.entries).insert(income(maxMoneyMinor));
      await db.into(db.rules).insert(rule(quantity: 100000));
      final occurrence = project(await db.readAll(), day, day).single;
      expect(occurrence.error, isNotNull);
      expect(occurrence.status, 'invalid');
      await expectLater(db.recordProjection(occurrence), throwsStateError);
      expect((await db.readAll()).entries, hasLength(1));
      await db.restore(await db.backup());
      expect((await db.readAll()).entries.single.amount, maxMoneyMinor);
    },
  );

  test('Planner commit recomputes stale amounts and preserves occurrence uniqueness', () async {
    await db.into(db.entries).insert(income(10000));
    await db.into(db.rules).insert(rule(rate: 2500));
    final old = project(await db.readAll(), day, day).single;
    expect(old.amount, 2500);
    await (db.update(db.entries)..where((e) => e.id.equals('income'))).write(
      const EntriesCompanion(amount: Value(20000)),
    );
    await db.recordProjection(old);
    await db.recordProjection(old);
    final expenses = (await db.readAll()).entries.where(
      (e) => e.kind == 'expense',
    );
    expect(expenses.single.amount, 5000);
    expect(expenses.single.occurrence, old.key);
  });

  test('Malformed raw logs and epochs reject restoration without replacing records', () async {
    await db.into(db.entries).insert(income(123));
    final original = jsonDecode(await db.backup()) as Map<String, dynamic>;
    final valid = {
      'id': 'log',
      'time': day.millisecondsSinceEpoch,
      'action': 'income',
      'title': 'Saved',
      'location': 'Location unavailable',
      'details': '{}',
    };
    for (final invalid in [
      {...valid, 'time': 'invalid-time'},
      {...valid, 'time': maxRecordEpoch + 1},
      {...valid, 'details': '[]'},
      {...valid, 'details': '{"position":42}'},
      {...valid, 'details': '{"position":{"lat":91,"lng":120}}'},
      {...valid, 'details': '{"locationTime":"bad"}'},
    ]) {
      await expectLater(
        db.restore(
          jsonEncode({
            ...original,
            'activityLogs': [invalid],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect((await db.readAll()).entries.single.amount, 123);
    }
    await expectLater(
      db.restore(
        jsonEncode({
          ...original,
          'activityLogs': [valid, valid],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
    expect((await db.readAll()).entries.single.amount, 123);
  });

  test(
    'Clock action instant stays fixed despite delayed optional GPS capture',
    () async {
      await db.pref('activityLogging', true);
      await db.pref('locationEnabled', true);
      final confirmed = DateTime.now().millisecondsSinceEpoch - 5000;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        NativeSession.channel,
        (call) async => jsonEncode({
          'lat': 14.6,
          'lng': 121.0,
          'accuracy': 10,
          'locationTime': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
      );
      final session = await RecordLocation.commit(
        db,
        () => db.clockIn('', at: confirmed),
        permission: () async => true,
      );
      expect(session.started, confirmed);
      final logs = await db.customSelect('SELECT * FROM activity_logs').get();
      expect(logs.single.data['time'], confirmed);
      expect(MapRecord.parse(logs.single.data), isNull);
    },
  );

  test('Batched native import acknowledges only committed batches and retries a later failure', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final queue = List.generate(
      405,
      (i) => <String, dynamic>{
        'id': 'event-$i',
        'action': 'rule_toast',
        'time': day.millisecondsSinceEpoch,
        'title': '$i',
      },
    );
    final batches = <int>[];
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      if (call.method == 'automationEvents') {
        return jsonEncode(queue.take(200).toList());
      }
      if (call.method == 'automationAck') {
        final ids = List<String>.from(call.arguments as List);
        // Each acknowledgement observes already committed data.
        final prefs = await db.readPreferences();
        for (final id in ids) {
          final i = int.parse(id.substring(6));
          expect(prefs['ruleToast:$id'], '$i');
        }
        batches.add(ids.length);
        queue.removeWhere((event) => ids.contains(event['id']));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
    );
    await db.customStatement(
      "CREATE TRIGGER inject_failure BEFORE INSERT ON preferences WHEN NEW.key = 'ruleToast:event-250' BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(AutomationSync.reconcile(db), throwsA(anything));
    expect(batches, [200]);
    expect(queue, hasLength(205));
    expect(
      (await db.readPreferences()).containsKey('ruleToast:event-200'),
      isFalse,
    );
    await db.customStatement('DROP TRIGGER inject_failure');
    await AutomationSync.reconcile(db);
    expect(queue, isEmpty);
    expect(batches, [200, 200, 5]);
    expect((await db.readPreferences())['ruleToast:event-404'], '404');
  });

  test('Dense Map clusters retain every record and separate on zoom without altering coordinates', () {
    final records = List.generate(
      1000,
      (i) => MapRecord(
        {'id': '$i', 'title': 'Log'},
        {},
        {},
        14.6 + i * 0.000001,
        121.0,
        day,
      ),
    );
    final overview = clusterMapRecords(records, 8);
    final detail = clusterMapRecords(records, 19);
    expect(overview.length, lessThan(5));
    expect(detail.length, greaterThan(overview.length));
    expect(
      detail.expand((group) => group).map((r) => r.id).toSet(),
      records.map((r) => r.id).toSet(),
    );
    expect(overview.first.last, same(records[overview.first.length - 1]));
  });

  test(
    'A pending overlay ending survives batches before its automatic start',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final started = day.millisecondsSinceEpoch;
      final ended = started + 10000;
      final queue = <Map<String, dynamic>>[
        ...List.generate(
          200,
          (i) => {
            'id': 'notice-$i',
            'action': 'rule_toast',
            'time': started,
            'title': '$i',
          },
        ),
        {
          'id': 'start-event',
          'action': 'auto_clock_in',
          'time': started,
          'started': started,
          'sessionId': 'later-start',
          'kind': 'Work',
          'title': 'Clocked in',
          'location': 'Location unavailable',
        },
      ];
      var pending = true, batch = 0;
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        if (call.method == 'automationEvents') {
          return jsonEncode(queue.take(200).toList());
        }
        if (call.method == 'pending') {
          return pending
              ? {'id': 'later-start', 'ended': ended, 'note': 'Confirmed note'}
              : null;
        }
        if (call.method == 'automationAck') {
          batch++;
          final ids = List<String>.from(call.arguments as List);
          queue.removeWhere((event) => ids.contains(event['id']));
        }
        if (call.method == 'acknowledge') {
          expect(batch, 1);
          final session = (await db.readAll()).sessions.single;
          expect(session.ended, ended);
          expect(session.note, 'Confirmed note');
          pending = false;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
      );
      await AutomationSync.reconcile(db);
      expect(pending, isFalse);
      expect(queue, isEmpty);
      expect((await db.readAll()).running, isNull);
    },
  );
}
