import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/map_records.dart';
import 'package:freki_hub/services.dart';
import 'package:freki_hub/automation_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var requests = 0;
  String? response;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.readAll();
    await db.pref('activityLogging', true);
    await db.pref('locationEnabled', true);
    requests = 0;
    response = jsonEncode({
      'lat': 14.6,
      'lng': 121.0,
      'accuracy': 12,
      'locationTime': DateTime.now().millisecondsSinceEpoch,
    });
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      expect(call.method, 'mapCurrentLocation');
      requests++;
      return response;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(NativeSession.channel, null);
    await db.close();
  });
  Future<List<Map<String, dynamic>>> logs() async =>
      (await db
              .customSelect('SELECT * FROM activity_logs ORDER BY time, id')
              .get())
          .map((row) => row.data)
          .toList();
  Entry entry(String id, String kind) => Entry(
    id: id,
    day: dayKey(DateTime.now()),
    kind: kind,
    amount: 100,
    currency: 'PHP',
    category: 'Other',
    method: 'Cash',
    note: '',
    occurrence: null,
  );
  Future<T> capture<T>(Future<T> Function() save, {bool allowed = true}) =>
      RecordLocation.commit(db, save, permission: () async => allowed);

  test('Session start/end and expense/income/savings store plottable action positions', () async {
    final running = await capture(() => db.clockIn('Work'));
    await capture(() => db.clockOut(running.id));
    for (final kind in ['expense', 'income', 'savings']) {
      await capture(() => db.into(db.entries).insert(entry(kind, kind)));
    }
    final rows = await logs();
    expect(rows, hasLength(5));
    expect(rows.every((row) => MapRecord.parse(row) != null), isTrue);
    expect(rows.every((row) => row['location'] == 'Recorded location'), isTrue);
    expect(requests, 5);
    final range = MapRange.period('day', DateTime.now());
    expect(await db.watchMapLogs(range.from, range.until).first, hasLength(5));
  });
  test(
    'Expired and invalid fixes cannot label a saved transaction as located',
    () async {
      for (final raw in [
        jsonEncode({
          'lat': 14.6,
          'lng': 121.0,
          'accuracy': 12,
          'locationTime': 1,
        }),
        jsonEncode({
          'lat': 200,
          'lng': 121.0,
          'accuracy': 12,
          'locationTime': DateTime.now().millisecondsSinceEpoch,
        }),
      ]) {
        response = raw;
        await capture(
          () =>
              db.into(db.entries).insert(entry('invalid:$requests', 'expense')),
        );
      }
      expect(
        (await logs()).every(
          (row) =>
              MapRecord.parse(row) == null &&
              row['location'] == 'Location unavailable',
        ),
        isTrue,
      );
      expect((await db.readAll()).entries, hasLength(2));
    },
  );
  test('Native replay preserves event positions without regressing the latest cache', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final events = [
      {
        'id': 'latest',
        'action': 'location',
        'title': 'Latest',
        'location': 'Latest place',
        'lat': 14.6,
        'lng': 121.0,
        'accuracy': 12,
        'locationTime': now,
        'time': now,
      },
      {
        'id': 'older',
        'action': 'location',
        'title': 'Older',
        'location': 'Older place',
        'lat': 14.7,
        'lng': 121.1,
        'accuracy': 12,
        'locationTime': now - 300000,
        'time': now - 300000,
      },
    ];
    var queued = true;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      if (call.method == 'automationEvents') {
        return jsonEncode(queued ? events : []);
      }
      if (call.method == 'automationAck') queued = false;
      return null;
    });
    await AutomationSync.reconcile(db);
    expect((await db.readAll()).prefs['locationName'], 'Latest place');
    final rows = await logs();
    expect(rows, hasLength(2));
    expect(rows.every((row) => MapRecord.parse(row) != null), isTrue);
    await AutomationSync.reconcile(db);
    expect(await logs(), hasLength(2));
  });
  test(
    'Unavailable or denied fixes save without borrowing the last position',
    () async {
      await capture(
        () => db.into(db.entries).insert(entry('first', 'expense')),
      );
      response = null;
      await capture(
        () => db.into(db.entries).insert(entry('second', 'income')),
      );
      await capture(
        () => db.into(db.entries).insert(entry('third', 'savings')),
        allowed: false,
      );
      final rows = await logs();
      expect(MapRecord.parse(rows.first), isNotNull);
      expect(
        rows
            .skip(1)
            .every(
              (row) =>
                  MapRecord.parse(row) == null &&
                  row['location'] == 'Location unavailable',
            ),
        isTrue,
      );
      expect((await db.readAll()).entries, hasLength(3));
      expect(requests, 2);
    },
  );
  test('Backdated session cannot inherit today position; Finance update gets its own log', () async {
    await capture(
      () => db
          .into(db.sessions)
          .insert(
            Session(
              id: 'old',
              day: '2020-01-01',
              kind: 'OJT',
              started: 1577836800000,
              ended: 1577840400000,
              note: '',
            ),
          ),
    );
    expect(MapRecord.parse((await logs()).single), isNull);
    final original = entry('edit', 'expense');
    await capture(() => db.into(db.entries).insert(original));
    await capture(
      () => db
          .into(db.entries)
          .insertOnConflictUpdate(original.copyWith(amount: 200)),
    );
    final updated = (await logs()).singleWhere(
      (row) => row['title'] == 'Updated expense',
    );
    expect(MapRecord.parse(updated)?.category, 'Finance');
    // Saving the same values is not a new activity.
    await capture(
      () => db
          .into(db.entries)
          .insertOnConflictUpdate(original.copyWith(amount: 200)),
    );
    expect(await logs(), hasLength(3));
  });
  test(
    'Disabled location and logging do not request access or a fix',
    () async {
      await db.pref('locationEnabled', false);
      await capture(() => db.into(db.entries).insert(entry('off', 'expense')));
      expect(MapRecord.parse((await logs()).single), isNull);
      await db.pref('locationEnabled', true);
      await db.pref('activityLogging', false);
      await capture(() => db.into(db.entries).insert(entry('quiet', 'income')));
      expect(await logs(), hasLength(1));
      expect(requests, 0);
    },
  );
  test(
    'Version 2 migration preserves records/logs and replaces stale triggers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'frekihub_position_migration_',
      );
      final file = File('${directory.path}/records.sqlite');
      final old = AppDatabase.forTesting(NativeDatabase(file));
      await old.pref('activityLogging', true);
      await old.into(old.entries).insert(entry('preserved', 'expense'));
      await old.customStatement('DROP TRIGGER log_transaction');
      await old.customStatement(
        "CREATE TRIGGER log_transaction AFTER INSERT ON entries BEGIN INSERT INTO activity_logs VALUES ('broken:' || NEW.id, 1, NEW.kind, 'Old trigger', 'Old place', '{}'); END",
      );
      await old.customStatement('PRAGMA user_version = 2');
      await old.close();
      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect((await upgraded.readAll()).entries.single.id, 'preserved');
        await upgraded.into(upgraded.entries).insert(entry('new', 'expense'));
        final rows = await upgraded
            .customSelect('SELECT * FROM activity_logs')
            .get();
        expect(rows, hasLength(2));
        expect(
          rows.every((row) => row.data['location'] == 'Location unavailable'),
          isTrue,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          3,
        );
      } finally {
        await upgraded.close();
        await file.delete();
        await directory.delete();
      }
    },
  );
  test('Failure rolls back sample and record together; stale coordinates stay unlocated', () async {
    await db.pref('locationName', 'Previous');
    await expectLater(
      capture<void>(() async {
        throw StateError('Rejected');
      }),
      throwsStateError,
    );
    expect((await db.readAll()).prefs['locationName'], 'Previous');
    await db.pref('locationSampleTime', 1);
    await db.pref(
      'locationDetails',
      jsonEncode({'lat': 14.6, 'lng': 121.0, 'locationTime': 1}),
    );
    await db.into(db.entries).insert(entry('stale', 'expense'));
    final row = (await logs()).single;
    expect(row['location'], 'Location unavailable');
    expect(MapRecord.decode(row['details'])['position'], '');
    expect(MapRecord.parse(row), isNull);
  });
}
