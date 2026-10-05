import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

class LogFailureDatabase extends AppDatabase {
  LogFailureDatabase() : super.forTesting(NativeDatabase.memory());
  int subscriptions = 0;
  final controller = StreamController<List<Map<String, dynamic>>>();
  @override
  Stream<List<Map<String, dynamic>>> watchActivityLogs() {
    subscriptions++;
    return subscriptions == 1 ? controller.stream : Stream.value([]);
  }
}

void main() {
  testWidgets(
    'Logs retain loaded rows on failure and Retry restores a usable empty state',
    (tester) async {
      final db = LogFailureDatabase();
      addTearDown(db.close);
      addTearDown(db.controller.close);
      final data = AppData([], [], [], {'activityLogging': 'true'});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWithValue(AsyncData(data)),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const Scaffold(body: LogsSheet()),
          ),
        ),
      );
      await tester.pump();
      db.controller.add([
        {
          'id': 'record',
          'time': DateTime(2026, 10, 5).millisecondsSinceEpoch,
          'action': 'clock_in',
          'title': 'Clocked in',
          'location': 'Location unavailable',
          'details': '{}',
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Clocked in'), findsOneWidget);
      db.controller.addError(StateError('Injected database read failure'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load activity logs'),
        findsOneWidget,
      );
      expect(find.text('Clocked in'), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(db.subscriptions, 2);
      expect(find.text('No activity yet'), findsOneWidget);
      expect(find.textContaining('Could not load activity logs'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Calendar remount restores selection/view and clamps leap-day year navigation',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() => db.readAll());
      final data = AppData([], [], [], {
        'calendarSelected': '2024-02-29',
        'calendarView': 'year',
      });
      Widget page() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(body: CalendarScreen(data: data)),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next year'), findsOneWidget);
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        expect((await db.readPreferences())['calendarSelected'], '2025-02-28');
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('2024'), findsWidgets);
      expect(find.byTooltip('Next year'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Session edit respects the chosen date and twelve-hour time formats',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final start = DateTime(2026, 10, 5, 15, 10);
      final session = Session(
        id: 'format',
        day: dayKey(start),
        kind: 'Work',
        started: start.millisecondsSinceEpoch,
        ended: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        note: '',
      );
      final data = AppData(
        [session],
        [],
        [],
        {'dateFormat': 'dd/MM/yyyy', 'clockFormat': '12'},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Scaffold(
              body: SessionForm(data: data, day: session.day, session: session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clock in · 05/10/2026, 3:10 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
