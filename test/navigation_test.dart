import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/main.dart';
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
    for (final inset in [80.0, 160.0, 280.0, 160.0, 80.0, 0.0]) {
      tester.view.padding = inset == 0
          ? const FakeViewPadding(bottom: 24)
          : FakeViewPadding.zero;
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getRect(find.byType(PillNavigation)), original);
      expect(tester.getRect(find.byType(TextField)), input);
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
    'Hold center, drag to expense, release selects; outside cancels',
    (tester) async {
      String? action;
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 400,
                child: PillNavigation(
                  index: 0,
                  onChanged: (value) => selected = value,
                  onQuickAdd: (value) => action = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(PillNavigation));
      await tester.tapAt(center - const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tapAt(center + const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(selected, 2);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Expense'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(find.text('Expense')));
      await tester.pump(const Duration(milliseconds: 160));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(action, 'expense');
      expect(find.text('Expense'), findsNothing);
      action = null;
      final cancel = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      await cancel.moveTo(const Offset(5, 5));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(action, isNull);
      expect(find.text('Expense'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
