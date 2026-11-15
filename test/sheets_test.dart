import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/design.dart';

Future<void> openSheet(
  WidgetTester tester,
  Widget content, {
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: Design.theme(reduced),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: KeyboardOverlay(child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => panel(context, content),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Keyboard lifts obscured sheet inputs without changing snap or slot sizes',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      await openSheet(
        tester,
        const PanelContent(
          header: Text('Input heading'),
          footer: Text('Input actions'),
          child: Column(
            children: [
              TextField(),
              TextField(keyboardType: TextInputType.number),
            ],
          ),
        ),
      );
      final sheet = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      for (final field in find.byType(TextField).evaluate().toList()) {
        await tester.showKeyboard(find.byWidget(field.widget));
        await tester.pump(const Duration(milliseconds: 300));
        final extent = sheet.size;
        final header = tester.getRect(find.text('Input heading'));
        final footer = tester.getRect(find.text('Input actions'));
        final input = tester.getRect(find.byWidget(field.widget));
        for (final inset in [80.0, 160.0, 280.0, 160.0, 80.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pumpAndSettle();
          expect(sheet.size, extent);
          expect(tester.getRect(find.text('Input heading')).size, header.size);
          expect(tester.getRect(find.text('Input actions')).size, footer.size);
          final currentInput = tester.getRect(find.byWidget(field.widget));
          expect(currentInput.size, input.size);
          expect(currentInput.bottom, lessThanOrEqualTo(800 - inset));
        }
        expect(tester.getRect(find.text('Input heading')), header);
        expect(tester.getRect(find.text('Input actions')), footer);
        expect(tester.getRect(find.byWidget(field.widget)), input);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Long form sheet keeps unobstructed top fields fixed and reveals bottom fields',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      const topFieldKey = ValueKey('top-field');
      const bottomFieldKey = ValueKey('bottom-field');
      await openSheet(
        tester,
        const PanelContent(
          header: Text('Long form'),
          footer: Text('Save / Cancel'),
          child: Column(
            children: [
              TextField(key: topFieldKey),
              SizedBox(height: 360),
              TextField(key: bottomFieldKey),
            ],
          ),
        ),
      );
      final sheet = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      final extent = sheet.size;
      expect(extent, closeTo(.70, .001));

      // Top field is already well above a 280px keyboard, so sheet does not shift.
      await tester.showKeyboard(find.byKey(topFieldKey));
      await tester.pumpAndSettle();
      final topInitial = tester.getRect(find.byKey(topFieldKey));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(sheet.size, extent);
      expect(tester.getRect(find.byKey(topFieldKey)), topInitial);

      // Bottom field sits inside the IME zone and lifts/scrolls clear of the keyboard.
      await tester.ensureVisible(find.byKey(bottomFieldKey));
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byKey(bottomFieldKey));
      await tester.pumpAndSettle();
      expect(sheet.size, extent);
      expect(
        tester.getRect(find.byKey(bottomFieldKey)).bottom,
        lessThanOrEqualTo(800 - 280),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets('Content fit, expand and dismiss (reduced: $reduced)', (
      tester,
    ) async {
      await openSheet(
        tester,
        const PanelContent(
          header: Text('Heading'),
          footer: Text('Actions'),
          child: SizedBox(height: 80, child: Text('Short content')),
        ),
        reduced: reduced,
      );
      final controller = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      final compact = controller.size;
      expect(compact, inExclusiveRange(.15, .70));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(.70, .001));
      await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(compact, .001));
      // Hold before release to check position-based snapping, without a fling.
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('panel-drag-handle'))),
      );
      await drag.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveBy(const Offset(0, -280));
      await tester.pump(const Duration(milliseconds: 300));
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(.70, .001));
      final down = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('panel-drag-handle'))),
      );
      await down.moveBy(const Offset(0, 24));
      await tester.pump(const Duration(milliseconds: 16));
      await down.moveBy(const Offset(0, 280));
      await tester.pump(const Duration(milliseconds: 300));
      await down.up();
      await tester.pumpAndSettle();
      expect(controller.size, closeTo(compact, .001));
      await tester.fling(
        find.byKey(const ValueKey('panel-drag-handle')),
        const Offset(0, 160),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Long content caps at 70%, scrolls independently of fixed slots',
    (tester) async {
      await openSheet(
        tester,
        PanelContent(
          header: const Text('Fixed heading'),
          footer: const Text('Fixed actions'),
          scrollable: true,
          child: ListView.builder(
            itemCount: 80,
            itemExtent: 48,
            itemBuilder: (_, index) => Text('Row $index'),
          ),
        ),
      );
      final controller = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      expect(controller.size, closeTo(.70, .001));
      final header = tester.getTopLeft(find.text('Fixed heading'));
      final footer = tester.getTopLeft(find.text('Fixed actions'));
      await tester.drag(find.byType(ListView), const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Fixed heading')), header);
      expect(tester.getTopLeft(find.text('Fixed actions')), footer);
      expect(find.text('Row 12'), findsOneWidget);
      expect(controller.size, closeTo(.70, .001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Short lazy lists fit and recompute when contents change', (
    tester,
  ) async {
    var count = 2;
    await openSheet(
      tester,
      StatefulBuilder(
        builder: (context, change) => PanelContent(
          header: TextButton(
            onPressed: () => change(() => count = 20),
            child: const Text('More'),
          ),
          scrollable: true,
          child: ListView.builder(
            itemCount: count,
            itemExtent: 48,
            itemBuilder: (_, index) => Text('Item $index'),
          ),
        ),
      ),
    );
    final controller = tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .controller!;
    expect(controller.size, lessThan(.70));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(.70, .001));
    expect(tester.takeException(), isNull);
  });
}
