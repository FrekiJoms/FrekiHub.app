import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  testWidgets(
    'Session drawer opens without errors, caps height and keeps nested inputs usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      final session = Session(
        id: 'drawer',
        day: dayKey(now),
        kind: 'Work',
        started: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ended: now.millisecondsSinceEpoch,
        note: 'Drawer check',
      );
      final data = AppData([session], [], [], {});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(true),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Consumer(
              builder: (c, ref, _) => Scaffold(
                body: Center(child: sessionTile(c, ref, data, session)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ListTile));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Session details'), findsOneWidget);
      expect(find.text('Session detail'), findsNothing);
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(sheet.controller!.size, lessThanOrEqualTo(.70));
      await tester.drag(
        find.byKey(const ValueKey('panel-drag-handle')),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(.70, .001));
      await tester.tap(find.text('Session type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('Study'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Clock in ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Clock in ·'));
      await tester.pumpAndSettle();
      expect(find.text('Select date'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Session details'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Selection sheet searches, selects and cancels without changing data',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String value = 'Option 1';
      int changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => selectField(
                'Category',
                value,
                List.generate(12, (i) => 'Option ${i + 1}'),
                (result) => setState(() {
                  value = result;
                  changes++;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      expect(find.text('Find an option'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option 12'));
      await tester.pumpAndSettle();
      expect(value, 'Option 12');
      expect(changes, 1);
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close selection'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    },
  );
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
      if (page is CalendarScreen) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.takeException(),
          isNull,
          reason: 'An empty calendar date must not sort a constant list',
        );
      }
      if (page is TodayScreen) {
        final balance = find.byKey(const ValueKey('home-balance-pill'));
        expect(
          find.descendant(of: balance, matching: find.text('Balance')),
          findsOneWidget,
        );
        final originalBalance = tester.getRect(balance);
        expect(find.textContaining('Current time · '), findsOneWidget);
        final headingPosition = tester.getTopLeft(find.text('Home.'));
        final date = find.textContaining(
          RegExp(
            r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), \d+ \w+$',
          ),
        );
        final datePosition = tester.getTopLeft(date);
        await tester.drag(find.byType(ListView).first, const Offset(0, -220));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getRect(balance).top, closeTo(73, .01));
        expect(tester.getRect(balance).right, closeTo(320 - 16, .01));
        expect(tester.getTopLeft(find.text('Home.')), headingPosition);
        expect(tester.getTopLeft(date), datePosition);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is FlipClock && widget.label == 'Current time',
          ),
          findsOneWidget,
        );
        tester
            .widget<ListView>(find.byType(ListView).first)
            .controller!
            .jumpTo(0);
        await tester.pump();
        expect(tester.getRect(balance), originalBalance);
      }
      for (final tooltip in [
        'Add record',
        'Add transaction',
        'Add session',
        'Add to selected day',
      ]) {
        expect(find.byTooltip(tooltip), findsNothing);
      }
      expect(
        tester.takeException(),
        isNull,
        reason: page.runtimeType.toString(),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets(
    'Home balance docks smoothly and returns with large text and safe insets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: Design.theme(true),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                padding: EdgeInsets.only(top: 24),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: SafeArea(
                  child: TodayScreen(data: AppData([], [], [], {})),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final pill = find.byKey(const ValueKey('home-balance-pill'));
      final original = tester.getRect(pill);
      final scroll = tester
          .widget<ListView>(find.byType(ListView).first)
          .controller!;
      scroll.jumpTo(60);
      await tester.pump();
      final halfway = tester.getRect(pill);
      scroll.jumpTo(200);
      await tester.pump();
      final docked = tester.getRect(pill);
      expect(docked.top, closeTo(24 + 16 + 48 + 9, .01));
      expect(docked.right, closeTo(320 - 16, .01));
      expect(halfway.left, greaterThan(original.left));
      expect(halfway.left, lessThan(docked.left));
      expect(halfway.top, greaterThan(docked.top));
      expect(halfway.top, lessThan(original.top));
      expect(docked.left, greaterThanOrEqualTo(16));
      expect(
        find.bySemanticsLabel(RegExp(r'^Total balance in ')),
        findsOneWidget,
      );
      scroll.jumpTo(60);
      await tester.pump();
      expect(tester.getRect(pill), halfway);
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.getRect(pill), original);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

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
