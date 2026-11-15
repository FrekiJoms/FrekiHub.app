import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  testWidgets(
    'Sessions compact layout shows inline summary, flat rows, filter sheet, sort, table toggle and contextual selection on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final day1 = DateTime(2026, 10, 5, 9, 0); // Monday
      final day2 = DateTime(2026, 11, 6, 14, 0); // Friday
      final sessions = [
        Session(
          id: 's1',
          day: dayKey(day1),
          kind: 'OJT',
          started: day1.millisecondsSinceEpoch,
          ended: day1.add(const Duration(hours: 2)).millisecondsSinceEpoch,
          note: 'Automatic · Office',
        ),
        Session(
          id: 's2',
          day: dayKey(day2),
          kind: 'Study',
          started: day2.millisecondsSinceEpoch,
          ended: day2.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
          note: 'Algorithms review',
        ),
      ];
      final data = AppData(sessions, [], [], {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(true),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                padding: EdgeInsets.only(bottom: 24),
                viewPadding: EdgeInsets.only(bottom: 24),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: Scaffold(body: HistoryScreen(data: data)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TIME & FOCUS LEDGER'), findsOneWidget);
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('2h 45m'), findsOneWidget);
      expect(find.text('2 RECORDS'), findsOneWidget);
      expect(find.text('Condition set'), findsOneWidget);
      // Summary and flat list do not wrap records in Surface cards.
      expect(find.byType(Surface), findsNothing);
      // Single continuous scroll view without nested vertical ListView in list mode.
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      // Both records are visible immediately without scrolling.
      expect(find.text('Algorithms review'), findsOneWidget);
      expect(find.text('Automatic · Office'), findsOneWidget);

      // Search filters rows and updates inline summary and record count.
      await tester.enterText(find.byType(TextField), 'Algorithms');
      await tester.pumpAndSettle();
      expect(find.text('1 OF 2 RECORDS'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('2 RECORDS'), findsOneWidget);

      // Open Filters sheet from search bar and filter by Type.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Date & time format'), findsOneWidget);
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OJT').last);
      await tester.pumpAndSettle();
      expect(find.text('Show 1 session'), findsOneWidget);
      await tester.tap(find.text('Show 1 session'));
      await tester.pumpAndSettle();
      expect(find.text('1 OF 2 RECORDS'), findsOneWidget);

      // Reset inline from toolbar.
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('2 RECORDS'), findsOneWidget);

      // Sort menu and direction toggle.
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duration').last);
      await tester.pumpAndSettle();
      expect(find.text('Duration'), findsOneWidget);
      await tester.tap(find.byTooltip('Descending; switch to ascending'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ascending; switch to descending'), findsOneWidget);

      // Switch to Table view and back to List view via compact options menu.
      await tester.tap(find.byTooltip('View and selection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table view'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scroll sideways for more columns'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('View and selection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List view'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scroll sideways for more columns'),
        findsNothing,
      );

      // Contextual selection via long press on a flat row.
      await tester.longPress(find.text('Algorithms review'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Delete 1'), findsOneWidget);
      await tester.tap(find.text('Select visible'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Delete 2'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sessions bulk delete and Date & time format sheet (via Filters) persist changes',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime(2026, 10, 5, 15, 10);
      await tester.runAsync(() async {
        await db
            .into(db.sessions)
            .insert(
              Session(
                id: 'del-1',
                day: dayKey(now),
                kind: 'Work',
                started: now.millisecondsSinceEpoch,
                ended: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
                note: 'To remove',
              ),
            );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: ref
                    .watch(dataProvider)
                    .when(
                      data: (data) => HistoryScreen(data: data),
                      loading: () => const SizedBox(),
                      error: (e, _) => Text('$e'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify compact section proportions on large mobile screen.
      final headerTop = tester.getTopLeft(find.text('TIME & FOCUS LEDGER')).dy;
      final summaryTop = tester.getTopLeft(find.text('1h 00m')).dy;
      final searchTop = tester.getTopLeft(find.byType(TextField)).dy;
      final toolbarTop = tester.getTopLeft(find.text('1 RECORD')).dy;
      final firstRowTop = tester.getTopLeft(find.text('To remove')).dy;
      expect(summaryTop - headerTop, lessThanOrEqualTo(125));
      expect(searchTop - summaryTop, lessThanOrEqualTo(140));
      expect(toolbarTop - searchTop, lessThanOrEqualTo(60));
      expect(firstRowTop, lessThan(420));

      // Change clock format via Date & time option inside Filters sheet.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Date & time format'));
      await tester.pumpAndSettle();
      expect(find.text('CLOCK FORMAT'), findsOneWidget);
      await tester.tap(find.textContaining('12-hour ·'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clock format updated'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.readPreferences()))!['clockFormat'],
        '12',
      );
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();

      // Contextual bulk delete via options menu in List view.
      await tester.tap(find.byTooltip('View and selection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('To remove'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Delete 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => db.readAll()))!.sessions, isEmpty);
      expect(find.text('Selected sessions deleted'), findsOneWidget);
      expect(find.byIcon(DataAction.deleted.icon), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
