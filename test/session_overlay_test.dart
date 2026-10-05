import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/automation_sync.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Historical overlay sample attaches to its ending without regressing the live cache', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pref('activityLogging', true);
    await db.pref('locationEnabled', true);
    final started = DateTime(2026, 10, 1, 8).millisecondsSinceEpoch;
    final running = await db.clockIn('Original', at: started);
    final ended = started + 10000;
    final live = DateTime.now().millisecondsSinceEpoch;
    await db.pref('locationName', 'Current place');
    await db.pref('locationSampleTime', live);
    await db.pref(
      'locationDetails',
      '{"lat":15,"lng":122,"locationTime":$live}',
    );
    await NativeSession.applyPending(db, {
      'id': running.id,
      'ended': ended,
      'note': 'Confirmed',
      'position': jsonEncode({
        'lat': 14.6,
        'lng': 121.0,
        'accuracy': 10,
        'locationTime': ended - 5000,
        'location': 'Office',
      }),
    });
    final row =
        (await db
                .customSelect(
                  "SELECT * FROM activity_logs WHERE action = 'clock_out'",
                )
                .get())
            .single
            .data;
    expect(row['location'], 'Office');
    expect(
      jsonDecode(jsonDecode(row['details'] as String)['position'])['lat'],
      14.6,
    );
    expect((await db.readPreferences())['locationSampleTime'], '$live');
    await NativeSession.applyPending(db, {
      'id': running.id,
      'ended': ended + 1000,
      'note': 'Replay',
      'position': '{"lat":16,"lng":123,"accuracy":10,"locationTime":$ended}',
    });
    expect((await db.readAll()).sessions.single.note, 'Confirmed');
    expect(
      (await db
          .customSelect(
            "SELECT * FROM activity_logs WHERE action = 'clock_out'",
          )
          .get()),
      hasLength(1),
    );
  });
  test(
    'Overlay note and confirmed time commit before acknowledgement',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final running = await db.clockIn('Original');
      final ended = running.started + 10000;
      var acknowledged = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSession.channel, (call) async {
            if (call.method == 'automationEvents') return jsonEncode([]);
            if (call.method == 'pending') {
              return acknowledged
                  ? null
                  : {'id': running.id, 'ended': ended, 'note': 'Overlay draft'};
            }
            if (call.method == 'acknowledge') {
              final saved = (await db.readAll()).sessions.single;
              expect(saved.ended, ended);
              expect(saved.note, 'Overlay draft');
              acknowledged = true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeSession.channel, null),
      );
      await AutomationSync.reconcile(db);
      expect(acknowledged, isTrue);
      await NativeSession.applyPending(db, {
        'id': running.id,
        'ended': ended + 1000,
        'note': 'Replay',
      });
      final saved = (await db.readAll()).sessions.single;
      expect(saved.ended, ended);
      expect(saved.note, 'Overlay draft');
    },
  );

  test('Invalid end rolls back note; legacy payload preserves note and empty drafts save', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final running = await db.clockIn('Original');
    await expectLater(
      NativeSession.applyPending(db, {
        'id': running.id,
        'ended': 'invalid',
        'note': 'Must roll back',
      }),
      throwsA(isA<TypeError>()),
    );
    expect((await db.readAll()).running!.note, 'Original');
    await NativeSession.applyPending(db, {
      'id': running.id,
      'ended': running.started + 1000,
    });
    expect((await db.readAll()).sessions.single.note, 'Original');
    final next = Session(
      id: 'next',
      day: '2099-01-01',
      kind: 'Work',
      started: running.started + 2000,
      ended: null,
      note: 'Clear me',
    );
    await db.into(db.sessions).insert(next);
    await NativeSession.applyPending(db, {
      'id': next.id,
      'ended': next.started + 1000,
      'note': '',
    });
    expect(
      (await db.readAll()).sessions.singleWhere((s) => s.id == next.id).note,
      '',
    );
  });

  for (final allowed in [false, true]) {
    testWidgets(
      'Permission hint stays readable with fixed actions ($allowed)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: Design.theme(allowed),
            builder: (context, child) => KeyboardOverlay(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      panel(context, OverlayPermissionHint(allowed: allowed)),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text(allowed ? 'Manage access' : 'Allow overlay').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Not now').hitTestable(), findsOneWidget);
        expect(find.text('You stay in control'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm wherever you are'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
