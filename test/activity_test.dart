import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/automation_sync.dart';
import 'package:freki_hub/services.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Queued automatic starts reconcile around a notification clock-out',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.readAll();
      var pending = true;
      var queued = true;
      final events = [
        {
          'id': 'event1',
          'action': 'auto_clock_in',
          'sessionId': 'first',
          'title': 'Clocked in',
          'time': 1790902800000,
          'started': 1790902800000,
          'location': 'Office',
          'kind': 'OJT',
        },
        {
          'id': 'event2',
          'action': 'auto_clock_in',
          'sessionId': 'second',
          'title': 'Clocked in',
          'time': 1790907000000,
          'started': 1790907000000,
          'location': 'School',
          'kind': 'Study',
        },
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSession.channel, (
            MethodCall call,
          ) async {
            switch (call.method) {
              case 'automationEvents':
                return jsonEncode(queued ? events : []);
              case 'pending':
                return pending
                    ? {
                        'id': 'first',
                        'ended': 1790906400000,
                        'note': 'Edited in overlay',
                      }
                    : null;
              case 'acknowledge':
                pending = false;
                return null;
              case 'automationAck':
                queued = false;
                return null;
              case 'automationConfig':
                return null;
              default:
                throw StateError('Unexpected method ${call.method}');
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeSession.channel, null),
      );
      await AutomationSync.reconcile(db);
      final data = await db.readAll();
      expect(data.sessions.length, 2);
      expect(
        data.sessions.firstWhere((s) => s.id == 'first').ended,
        1790906400000,
      );
      expect(data.running?.id, 'second');
      expect(
        data.sessions.firstWhere((s) => s.id == 'first').note,
        'Edited in overlay',
      );
      await AutomationSync.reconcile(db);
      expect((await db.readAll()).sessions.length, 2);
    },
  );
  test(
    'Version 1 upgrade preserves sessions and creates log storage',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'frekihub_log_migration_',
      );
      final file = File('${folder.path}/data.sqlite');
      final initial = AppDatabase.forTesting(NativeDatabase(file));
      await initial
          .into(initial.sessions)
          .insert(
            Session(
              id: 'existing',
              day: '2026-10-02',
              kind: 'OJT',
              started: 1790902800000,
              ended: null,
              note: 'Existing data',
            ),
          );
      for (final name in ['session_start', 'session_end', 'transaction']) {
        await initial.customStatement('DROP TRIGGER log_$name');
      }
      await initial.customStatement('DROP TABLE activity_logs');
      await initial.customStatement('PRAGMA user_version = 1');
      await initial.close();
      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      expect((await upgraded.readAll()).sessions.single.id, 'existing');
      expect(
        await upgraded.customSelect('SELECT * FROM activity_logs').get(),
        isEmpty,
      );
      await upgraded.close();
      await file.delete();
      await folder.delete();
    },
  );
  test('Activity logging is opt-in and backup preserves logs and purchase deduplication', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.readAll();
    await db
        .into(db.sessions)
        .insert(
          Session(
            id: 'manual',
            day: '2026-10-02',
            kind: 'OJT',
            started: 1790902800000,
            ended: null,
            note: 'Office',
          ),
        );
    expect(await db.customSelect('SELECT * FROM activity_logs').get(), isEmpty);
    await db.pref('activityLogging', true);
    await db.pref('locationName', 'Office');
    await db.pref('locationSampleTime', DateTime.now().millisecondsSinceEpoch);
    await db.clockOut('manual', at: 1790906400000);
    final purchase = Entry(
      id: 'purchase:ref123',
      day: '2026-10-02',
      kind: 'expense',
      amount: 12550,
      currency: 'PHP',
      category: 'Food',
      method: 'Payment app',
      note: "Coffee's",
      occurrence: 'purchase:ref123',
    );
    await db.into(db.entries).insert(purchase, mode: InsertMode.insertOrIgnore);
    await db.into(db.entries).insert(purchase, mode: InsertMode.insertOrIgnore);
    expect((await db.readAll()).entries.length, 1);
    final logs = await db
        .customSelect('SELECT * FROM activity_logs ORDER BY time')
        .get();
    expect(logs.length, 2);
    expect(logs.last.data['location'], 'Office');
    final backup = await db.backup();
    expect((jsonDecode(backup)['activityLogs'] as List).length, 2);
    await db.restore(backup);
    expect((await db.readAll()).entries.length, 1);
    expect(
      (await db.customSelect('SELECT * FROM activity_logs').get()).length,
      2,
    );
    await db.pref('activityLogging', false);
    await db
        .into(db.entries)
        .insert(
          purchase.copyWith(id: 'second', occurrence: const Value('second')),
        );
    expect(
      (await db.customSelect('SELECT * FROM activity_logs').get()).length,
      2,
    );
    await db.clear();
    expect(await db.customSelect('SELECT * FROM activity_logs').get(), isEmpty);
  });
}
