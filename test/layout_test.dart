import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  testWidgets('Main pages fit a narrow screen with enlarged text', (
    tester,
  ) async {
    final handler = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      handler?.call(details);
    };
    addTearDown(() => FlutterError.onError = handler);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final day = dayKey(DateTime.now());
    final data = AppData(
      [
        Session(
          id: 'audit',
          day: day,
          kind: 'Work',
          started: 1000,
          ended: 3601000,
          note: 'Automatic · Office',
        ),
      ],
      [],
      [],
      {},
    );
    for (final page in [
      TodayScreen(data: data),
      CalendarScreen(data: data),
      HistoryScreen(data: data),
      BudgetScreen(data: data),
      SettingsScreen(data: data),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWith((ref) => Stream.value(data)),
          ],
          child: MaterialApp(
            theme: Design.theme(true),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: Scaffold(body: page),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.takeException(),
        isNull,
        reason: page.runtimeType.toString(),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets('External filter reset updates the displayed selection', (
    tester,
  ) async {
    String value = 'Work';
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return selectField('Type', value, ['All', 'Work'], (_) {});
            },
          ),
        ),
      ),
    );
    expect(find.text('Work').hitTestable(), findsOneWidget);
    change(() => value = 'All');
    await tester.pump();
    expect(find.text('All').hitTestable(), findsOneWidget);
  });
}
