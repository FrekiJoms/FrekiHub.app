import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';
import 'package:intl/intl.dart';

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required AppDatabase db,
    required AppData data,
    Size size = const Size(320, 720),
    double textScale = 1.3,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataProvider.overrideWith((ref) => Stream.value(data)),
        ],
        child: MaterialApp(
          theme: Design.theme(false),
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: Scaffold(body: CalendarScreen(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownScope(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'All Calendar views and record labels fit narrow screen with enlarged text',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final morning = DateTime(2025, 3, 19, 9, 0).millisecondsSinceEpoch;
      final overlap = DateTime(2025, 3, 19, 9, 30).millisecondsSinceEpoch;
      final data = AppData(
        [
          Session(
            id: 's1',
            kind: 'focus',
            started: morning,
            ended: morning + 5400 * 1000,
            day: '2025-03-19',
            note: 'Deep work block',
          ),
          Session(
            id: 's2',
            kind: 'rest',
            started: overlap,
            ended: overlap + 2700 * 1000,
            day: '2025-03-19',
            note: 'Break',
          ),
        ],
        [
          const Entry(
            id: 'e1',
            day: '2025-03-19',
            kind: 'expense',
            amount: 15000,
            currency: 'PHP',
            category: 'Coffee',
            method: 'Cash',
            note: 'Espresso',
          ),
          const Entry(
            id: 'e2',
            day: '2025-03-19',
            kind: 'income',
            amount: 50000,
            currency: 'PHP',
            category: 'Freelance',
            method: 'Bank',
            note: '',
          ),
        ],
        const [],
        const {'calendarSelected': '2025-03-19', 'calendarView': 'month'},
      );

      await pumpCalendar(tester, db: db, data: data);
      expect(find.text('March 2025'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Toggle record labels mode in anchored options menu.
      await tester.tap(find.byTooltip('Calendar options'));
      await tester.pumpAndSettle();
      expect(find.text('Show record labels'), findsOneWidget);
      await tester.tap(find.text('Show record labels'));
      await tester.pumpAndSettle();
      expect(find.text('focus'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Switch to Week view and confirm overlapping sessions sit in separate lanes.
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      final focusLeft = tester.getRect(find.text('focus').first).left;
      final restLeft = tester.getRect(find.text('rest').first).left;
      expect(focusLeft, isNot(closeTo(restLeft, 1.0)));
      expect(tester.takeException(), isNull);

      // Switch to Day view.
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Switch to Year view.
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('Mar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await teardownScope(tester);
    },
  );

  testWidgets(
    'Month grid collapses smoothly to selected week row on tap and drag',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final data = AppData(const [], const [], const [], const {
        'calendarSelected': '2025-03-19',
        'calendarView': 'month',
      });

      await pumpCalendar(tester, db: db, data: data, textScale: 1.0);
      final expandedDay19 = tester.getRect(find.text('19').first);
      final expandedDay2 = tester.getRect(find.text('2').first);
      expect(expandedDay19.top, greaterThan(expandedDay2.top));

      await tester.tap(find.bySemanticsLabel('Collapse month grid'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Expand month grid'), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        expect((await db.readPreferences())['calendarCollapsed'], '1');
      });

      // Day 19 glided up into the single collapsed week row.
      final collapsedDay19 = tester.getRect(find.text('19').first);
      expect(collapsedDay19.top, lessThan(expandedDay19.top));

      // Vertical drag down re-expands smoothly.
      await tester.drag(
        find.bySemanticsLabel('Expand month grid'),
        const Offset(0, 64),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Collapse month grid'), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        expect((await db.readPreferences())['calendarCollapsed'], '0');
      });

      expect(tester.takeException(), isNull);
      await teardownScope(tester);
    },
  );

  testWidgets(
    'Horizontal swipe navigates periods and Today pill jumps to current day',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final data = AppData(const [], const [], const [], const {
        'calendarSelected': '2025-03-15',
        'calendarView': 'month',
      });

      await pumpCalendar(tester, db: db, data: data, textScale: 1.0);
      expect(find.text('March 2025'), findsOneWidget);

      await tester.fling(find.text('15').first, const Offset(-220, 0), 700);
      await tester.pumpAndSettle();
      expect(find.text('April 2025'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Jump to today'));
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(find.text(DateFormat('MMMM yyyy').format(today)), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        expect((await db.readPreferences())['calendarSelected'], dayKey(today));
      });
      expect(find.bySemanticsLabel('Jump to today'), findsNothing);
      expect(tester.takeException(), isNull);
      await teardownScope(tester);
    },
  );

  testWidgets(
    'DayPanel opens from agenda Sheet button with sorted sessions and entries',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final early = DateTime(2025, 3, 19, 8, 0).millisecondsSinceEpoch;
      final late = DateTime(2025, 3, 19, 14, 0).millisecondsSinceEpoch;
      final data = AppData(
        [
          Session(
            id: 's-late',
            kind: 'focus',
            started: late,
            ended: late + 1800 * 1000,
            day: '2025-03-19',
            note: 'Afternoon sprint',
          ),
          Session(
            id: 's-early',
            kind: 'rest',
            started: early,
            ended: early + 900 * 1000,
            day: '2025-03-19',
            note: 'Morning stretch',
          ),
        ],
        [
          const Entry(
            id: 'e1',
            day: '2025-03-19',
            kind: 'expense',
            amount: 9500,
            currency: 'PHP',
            category: 'Lunch',
            method: 'Card',
            note: 'Ramen',
          ),
        ],
        const [],
        const {'calendarSelected': '2025-03-19', 'calendarView': 'month'},
      );

      await pumpCalendar(tester, db: db, data: data, textScale: 1.0);
      await tester.tap(find.text('Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(DayPanel), findsOneWidget);
      final stretchTop = tester.getRect(find.text('Morning stretch').last).top;
      final sprintTop = tester.getRect(find.text('Afternoon sprint').last).top;
      expect(stretchTop, lessThan(sprintTop));
      expect(find.text('Lunch'), findsWidgets);

      expect(tester.takeException(), isNull);
      await teardownScope(tester);
    },
  );
}
