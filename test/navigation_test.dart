import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/main.dart';
import 'package:freki_hub/screens.dart';
import 'package:freki_hub/startup.dart';

void main() {
  testWidgets(
    'Height-only keyboard resizing reuses content; width and theme refresh it',
    (tester) async {
      var builds = 0;
      var height = 600.0, width = 360.0;
      var dark = false;
      late StateSetter change;
      final layout = WidthLayoutBuilder(
        builder: (context, availableWidth) {
          builds++;
          return ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Text('$availableWidth'),
          );
        },
      );
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return MaterialApp(
              theme: Design.theme(dark),
              home: Center(
                child: SizedBox(width: width, height: height, child: layout),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final first = builds;
      for (final next in [540.0, 480.0, 420.0, 340.0]) {
        change(() => height = next);
        await tester.pump();
      }
      expect(builds, first);
      change(() => width = 320);
      await tester.pump();
      expect(builds, greaterThan(first));
      final narrow = builds;
      change(() => dark = true);
      await tester.pumpAndSettle();
      expect(builds, greaterThan(narrow));
      expect(find.text('320.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Keyboard overlays Home without moving content or navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
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
    messenger.setMockMethodCallHandler(
      const MethodChannel('frekihub/session'),
      (call) async => call.method == 'automationEvents' ? '[]' : null,
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataProvider.overrideWith(
            (ref) => Stream.value(AppData([], [], [], {})),
          ),
          graphicsProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: Design.theme(false),
          builder: (_, child) => KeyboardOverlay(child: child!),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final original = tester.getRect(find.byType(PillNavigation));
    final input = tester.getRect(find.byType(TextField));
    var scrolled = false;
    for (final inset in [80.0, 160.0, 280.0, 160.0, 80.0, 0.0]) {
      tester.view.padding = inset == 0
          ? const FakeViewPadding(bottom: 24)
          : FakeViewPadding.zero;
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getRect(find.byType(PillNavigation)), original);
      final current = tester.getRect(find.byType(TextField));
      if (input.bottom <= 800 - inset - 16 && !scrolled) {
        expect(current, input);
      } else {
        scrolled = true;
        expect(current.top, greaterThanOrEqualTo(0));
        expect(current.bottom, lessThanOrEqualTo(800 - inset));
      }
      expect(
        MediaQuery.viewInsetsOf(tester.element(find.byType(TextField))),
        EdgeInsets.zero,
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Central plus button centers in pill, short-taps radial menu and preserves long-press quick add',
    (tester) async {
      final actionsTriggered = <String>[];
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 400,
                child: PillNavigation(
                  index: 0,
                  onChanged: (value) => selected = value,
                  onQuickAdd: actionsTriggered.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pillRect = tester.getRect(find.byType(PillNavigation));
      final plusFinder = find.byKey(const ValueKey('nav-plus-button'));
      expect(plusFinder, findsOneWidget);
      final plusRect = tester.getRect(plusFinder);
      expect(plusRect.center.dx, closeTo(pillRect.center.dx, 0.01));
      expect(plusRect.center.dy, closeTo(pillRect.center.dy, 0.01));

      await tester.tap(find.bySemanticsLabel('Map'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tap(find.bySemanticsLabel('Sessions'));
      await tester.pumpAndSettle();
      expect(selected, 2);

      // Short tap opens radial menu and never executes quick-add or drag menu.
      await tester.tap(plusFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('radial-action-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-menu')), findsNothing);
      expect(actionsTriggered, isEmpty);

      // Staggered outward expansion from the exact center of the + button.
      final firstItemEarly = tester.getCenter(
        find.byKey(const ValueKey('radial-action-session')),
      );
      final lastItemEarly = tester.getCenter(
        find.byKey(const ValueKey('radial-action-rule')),
      );
      expect(
        (firstItemEarly - plusRect.center).distance,
        greaterThan((lastItemEarly - plusRect.center).distance),
      );

      await tester.pumpAndSettle();
      for (final kind in ['session', 'expense', 'income', 'savings', 'rule']) {
        final itemRect = tester.getRect(
          find.byKey(ValueKey('radial-action-$kind')),
        );
        expect(itemRect.left, greaterThanOrEqualTo(0));
        expect(itemRect.right, lessThanOrEqualTo(800));
        expect(itemRect.top, greaterThanOrEqualTo(0));
        expect((itemRect.center - plusRect.center).distance, greaterThan(60));
      }

      // Closing animation uses reverse stagger and returns items toward center.
      await tester.tap(find.byKey(const ValueKey('radial-close-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final firstItemClosing = tester.getCenter(
        find.byKey(const ValueKey('radial-action-session')),
      );
      final lastItemClosing = tester.getCenter(
        find.byKey(const ValueKey('radial-action-rule')),
      );
      expect(
        (lastItemClosing - plusRect.center).distance,
        lessThan((firstItemClosing - plusRect.center).distance),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);
      expect(actionsTriggered, isEmpty);

      // Short tap then selecting a radial item triggers action once and closes.
      await tester.tap(plusFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('radial-action-income')));
      await tester.pumpAndSettle();
      expect(actionsTriggered, ['income']);
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);
      actionsTriggered.clear();

      // Instant swipe on '+' (0ms hold) opens the radial menu immediately and selects the swiped action.
      final center = tester.getCenter(plusFinder);
      final swipe = await tester.startGesture(center);
      await swipe.moveBy(const Offset(0, -48));
      await tester.pump();
      expect(find.byKey(const ValueKey('radial-action-menu')), findsOneWidget);
      await swipe.up();
      await tester.pumpAndSettle();
      expect(actionsTriggered, ['income']);
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);
      actionsTriggered.clear();

      // Fast hold (150ms) on '+' opens the radial menu and drag-release selects radial item.
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('radial-action-menu')), findsOneWidget);
      expect(find.text('Drag to add · release to select'), findsNothing);
      final expenseItem = find.byKey(const ValueKey('radial-action-expense'));
      expect(expenseItem, findsOneWidget);
      await gesture.moveTo(tester.getCenter(expenseItem));
      await tester.pump(const Duration(milliseconds: 160));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(actionsTriggered, ['expense']);
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);

      // Releasing outside radial items cancels without firing an action.
      actionsTriggered.clear();
      final cancel = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await cancel.moveTo(const Offset(5, 5));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(actionsTriggered, isEmpty);
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);

      // Pointer cancellation during gesture cleans up without firing actions.
      final interrupted = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('radial-action-menu')), findsOneWidget);
      await interrupted.cancel();
      await tester.pumpAndSettle();
      expect(actionsTriggered, isEmpty);
      expect(find.byKey(const ValueKey('radial-action-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deferred AppShell tabs reflect new transactions, wallet removals, and deleted sessions immediately',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      messenger.setMockMethodCallHandler(
        const MethodChannel('frekihub/session'),
        (call) async => call.method == 'automationEvents' ? '[]' : null,
      );

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final today = dayKey(DateTime.now());
      final started = DateTime.now()
          .subtract(const Duration(minutes: 45))
          .millisecondsSinceEpoch;
      var current = AppData(
        [
          Session(
            id: 's1',
            day: today,
            kind: 'Work',
            started: started,
            ended: started + 30 * 60 * 1000,
            note: 'Client call',
          ),
        ],
        const [],
        const [],
        {
          'methods': jsonEncode(['Cash', 'GCash']),
          'walletOrder': jsonEncode(['GCash', 'Cash']),
        },
      );
      late final StreamController<AppData> controller;
      controller = StreamController<AppData>.broadcast(
        onListen: () {
          scheduleMicrotask(() {
            if (!controller.isClosed) controller.add(current);
          });
        },
      );
      addTearDown(() async {
        await controller.close();
        await db.close();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWith((ref) => controller.stream),
            graphicsProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            builder: (_, child) => KeyboardOverlay(child: child!),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Navigate to Finance (deferred tab 3) and wait past transition, 120ms stagger, and Entrance fade.
      await tester.tap(find.bySemanticsLabel('Finance'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^GCash wallet')), findsOneWidget);

      // Emit new income + removed GCash wallet and verify Finance updates immediately.
      current = AppData(
        current.sessions,
        [
          Entry(
            id: 'e1',
            day: today,
            kind: 'income',
            amount: 50000,
            currency: 'PHP',
            category: 'Salary',
            method: 'Cash',
            note: 'Payday bonus',
          ),
        ],
        const [],
        {
          'methods': jsonEncode(['Cash']),
          'hiddenWallets': jsonEncode(['gcash']),
          'walletOrder': jsonEncode(['Cash']),
        },
      );
      controller.add(current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.bySemanticsLabel(RegExp('^GCash wallet')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Cash wallet')), findsOneWidget);
      expect(find.text(money(50000, 'PHP')), findsWidgets);

      // Navigate to Sessions (deferred tab 2) and wait past transition, stagger, and Entrance fade.
      await tester.tap(find.bySemanticsLabel('Sessions'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Client call'), findsOneWidget);

      // Delete the session in AppData and verify Sessions reflects removal immediately.
      current = AppData(const [], current.entries, const [], current.prefs);
      controller.add(current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Client call'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'GlassCircleButton matches 48x48 circular LiquidGlassStyle surface',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: Center(
              child: GlassCircleButton(
                tooltip: 'Settings',
                icon: Icons.settings,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(GlassCircleButton);
      expect(tester.getSize(finder), const Size(48, 48));
      final chromeFinder = find.byType(Chrome);
      expect(tester.getSize(chromeFinder), const Size(38, 38));
      final chrome = tester.widget<Chrome>(chromeFinder);
      expect(chrome.borderRadius, 19);
      final lightDeco = LiquidGlassStyle.surfaceDecoration(
        tester.element(finder),
        radius: 19,
      );
      expect(lightDeco.color!.a, closeTo(.62, .001));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(true),
          home: Scaffold(
            body: Center(
              child: GlassCircleButton(
                tooltip: 'Settings',
                icon: Icons.settings,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final darkDeco = LiquidGlassStyle.surfaceDecoration(
        tester.element(finder),
        radius: 19,
      );
      expect(darkDeco.color!.a, closeTo(.52, .001));
      expect(tester.takeException(), isNull);
    },
  );
}
