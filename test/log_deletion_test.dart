import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/rule_language.dart';
import 'package:freki_hub/screens.dart';

Map<String, dynamic> event(String id, int time) => {
  'id': id,
  'time': time,
  'action': 'custom_log',
  'title': id,
  'lat': 14.5,
  'lng': 121.0,
  'locationTime': time,
};

class FailingDeletionDatabase extends AppDatabase {
  FailingDeletionDatabase() : super.forTesting(NativeDatabase.memory());
  @override
  Future<int> deleteActivityLog(String id) =>
      Future.error(StateError('Deletion failed'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Deletion updates both streams and observables, retains records, and survives replay/backup', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(restored.close);
    final time = DateTime(2026, 10, 6, 10).millisecondsSinceEpoch;
    await db.clockIn('Keep this session', at: time);
    await db
        .into(db.entries)
        .insert(
          Entry(
            id: 'finance',
            day: '2026-10-06',
            kind: 'expense',
            amount: 100,
            currency: 'PHP',
            category: 'Food',
            method: 'Cash',
            note: 'Keep this expense',
            occurrence: null,
          ),
        );
    await db.addActivity(event('Older', time));
    await db.addActivity(event('Latest', time + 1000));
    final activity = db.watchActivityLogs().firstWhere(
      (rows) => rows.length == 1,
    );
    final map = db
        .watchMapLogs(DateTime(2026, 10, 6), DateTime(2026, 10, 7))
        .firstWhere((rows) => rows.length == 1);
    expect(await db.deleteActivityLog('Latest'), 1);
    expect((await activity).single['id'], 'Older');
    expect((await map).single['id'], 'Older');
    final data = await db.readAll();
    expect(data.sessions.single.note, 'Keep this session');
    expect(data.entries.single.note, 'Keep this expense');
    final snapshot = RuleCatalog.snapshot(data);
    expect(snapshot['activity_logs.count'], 1);
    expect(snapshot['activity_logs.last.title'], 'Older');
    expect(snapshot.keys.where((k) => k.contains('deletedLog:')), isEmpty);
    await db.addActivity(event('Latest', time + 1000));
    expect(await db.deleteActivityLog('missing'), 0);
    await restored.restore(await db.backup());
    await restored.addActivity(event('Latest', time + 1000));
    expect((await restored.watchActivityLogs().first).single['id'], 'Older');
    expect(await restored.deleteActivityLog('Older'), 1);
    final empty = RuleCatalog.snapshot(await restored.readAll());
    expect(empty['activity_logs.count'], 0);
    expect(empty['activity_logs.last.title'], '');
    expect(empty['activity_logs.last.action'], '');
  });

  test('A failed deletion transaction retains its log and does not leave a tombstone', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.addActivity(
      event('Keep', DateTime(2026, 10, 6).millisecondsSinceEpoch),
    );
    await expectLater(
      db.transaction(() async {
        await db.deleteActivityLog('Keep');
        throw StateError('Rollback');
      }),
      throwsStateError,
    );
    expect((await db.watchActivityLogs().first).single['id'], 'Keep');
    expect((await db.readAll()).prefs.containsKey('deletedLog:Keep'), isFalse);
  });

  for (final failing in [false, true]) {
    testWidgets(
      'Expanded log deletion confirms, cancels quietly and reports commit result (failure: $failing)',
      (tester) async {
        final db = failing
            ? FailingDeletionDatabase()
            : AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final data = (await tester.runAsync(() async {
          await db.addActivity(
            event('Example log', DateTime(2026, 10, 6).millisecondsSinceEpoch),
          );
          return db.readAll();
        }))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              dataProvider.overrideWithValue(AsyncData(data)),
            ],
            child: MaterialApp(
              theme: Design.theme(false),
              home: const Scaffold(body: LogsSheet()),
            ),
          ),
        );
        Future<void> settle() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
        }

        await settle();
        expect(find.text('Delete log'), findsNothing);
        await tester.tap(find.text('Example log'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete log'));
        await tester.pumpAndSettle();
        expect(find.text('Delete this log?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('top-toast-pill')), findsNothing);
        await tester.tap(find.text('Delete log'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await settle();
        if (failing) {
          expect(find.text('Example log'), findsOneWidget);
          expect(find.text('Deletion failed'), findsOneWidget);
          expect(find.text('Log deleted'), findsNothing);
        } else {
          expect(find.text('Example log'), findsNothing);
          expect(find.text('No activity yet'), findsOneWidget);
          expect(find.text('Log deleted'), findsOneWidget);
          expect(find.byIcon(DataAction.deleted.icon), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
