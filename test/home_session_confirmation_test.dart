import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'Clock-out requires confirmation; cancel and Back keep running ($reduced)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final session = await db.clockIn('Session note');
        var now = DateTime.fromMillisecondsSinceEpoch(session.started)
            .add(const Duration(minutes: 1));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: Design.theme(reduced),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                  disableAnimations: reduced,
                ),
                child: KeyboardOverlay(child: child!),
              ),
              home: Scaffold(
                body: TodayScreen(
                  data: AppData([session], [], [], {}),
                  clockNow: () => now,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        Future<void> frames() async {
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull);
          }
        }

        await tester.ensureVisible(find.text('Clock out'));
        await tester.tap(find.text('Clock out'));
        await frames();
        expect(find.text('End this session?'), findsOneWidget);
        expect(find.text('End session').hitTestable(), findsOneWidget);
        expect(find.text('Keep running').hitTestable(), findsOneWidget);
        final noteField = find.byKey(const ValueKey('end-session-note'));
        expect(
          tester.widget<TextField>(noteField).controller!.text,
          'Session note',
        );
        await tester.enterText(noteField, 'Discard this change');
        await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
        await frames();
        expect(find.text('00:01:00'), findsOneWidget);
        expect((await db.readAll()).running?.id, session.id);

        expect((await db.readAll()).sessions.single.note, 'Session note');
        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('00:01:02'), findsOneWidget);
        await tester.ensureVisible(find.text('Keep running'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Keep running'));
        await frames();
        expect(find.text('End this session?'), findsNothing);
        expect((await db.readAll()).running?.id, session.id);

        await tester.tap(find.text('Clock out'));
        await frames();
        expect(
          tester.widget<TextField>(noteField).controller!.text,
          'Session note',
        );
        await tester.enterText(noteField, 'Discard on Back');
        await tester.binding.handlePopRoute();
        await frames();
        expect(find.text('End this session?'), findsNothing);
        expect((await db.readAll()).running?.id, session.id);
        expect((await db.readAll()).sessions.single.note, 'Session note');

        await tester.tap(find.text('Clock out'));
        await frames();
        await tester.enterText(noteField, '  Completed the design review  ');
        await tester.ensureVisible(find.text('End session'));
        await tester.pump(const Duration(milliseconds: 300));
        final endAgain = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'End session'),
            )
            .onPressed!;
        await tester.tap(find.text('End session'));
        endAgain();
        await frames();
        final saved = await tester.runAsync(() => db.readAll());
        expect(saved!.running, isNull);
        expect(saved.sessions, hasLength(1));
        expect(saved.sessions.single.note, 'Completed the design review');
        expect(saved.sessions.single.ended, isNotNull);
        expect(find.text('End this session?'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
