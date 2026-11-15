import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  testWidgets(
    'Sessions page shows summary, filters, sorting, list/table views and selection on narrow screen',
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
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: Scaffold(body: HistoryScreen(data: data)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('SESSION SUMMARY'), findsOneWidget);
      expect(find.text('2h 45m'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(find.text('2 records · 02:45:00 total'), findsOneWidget);
      expect(find.text('Condition set'), findsOneWidget);

      // Search filters rows and updates summary.
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Algorithms');
      await tester.pumpAndSettle();
      expect(find.text('FILTERED SESSIONS'), findsOneWidget);
      await tester.ensureVisible(find.text('1 record · 00:45:00 total'));
      await tester.pumpAndSettle();
      expect(find.text('1 record · 00:45:00 total'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('2 records · 02:45:00 total'));
      await tester.pumpAndSettle();
      expect(find.text('2 records · 02:45:00 total'), findsOneWidget);

      // Expand filters and filter by Type.
      await tester.ensureVisible(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OJT').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1 record · 02:00:00 total'));
      await tester.pumpAndSettle();
      expect(find.text('1 record · 02:00:00 total'), findsOneWidget);
      await tester.ensureVisible(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('2 records · 02:45:00 total'));
      await tester.pumpAndSettle();
      expect(find.text('2 records · 02:45:00 total'), findsOneWidget);

      // Sort menu and direction toggle.
      await tester.drag(find.byType(ListView).first, const Offset(0, 220));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sort · Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort · Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duration').last);
      await tester.pumpAndSettle();
      expect(find.text('Sort · Duration'), findsOneWidget);
      await tester.tap(find.byTooltip('Descending; switch to ascending'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ascending; switch to descending'), findsOneWidget);

      // Switch to Table view and back to List view via segmented control.
      await tester.tap(find.byTooltip('Table view'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scroll sideways for more columns'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Scroll sideways for more columns'),
        findsNothing,
      );

      // Selection mode works in List view without forcing Table view.
      await tester.ensureVisible(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tap sessions to select'));
      await tester.pumpAndSettle();
      expect(find.text('Tap sessions to select'), findsOneWidget);
      await tester.tap(find.text('Select visible'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Delete 2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Done'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sessions bulk delete and Date & time format sheet persist changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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

      // Change clock format via Date & time sheet.
      await tester.tap(find.text('Date & time'));
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

      // Bulk delete in List view.
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
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
