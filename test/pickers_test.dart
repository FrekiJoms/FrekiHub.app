import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('Jump to now scrolls date/time wheels; reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? chosen;
      TimeOfDay? chosenTime;
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(reduced),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      chosen = await showWheelDatePicker(
                        context: context,
                        initialDate: DateTime(2001),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                    },
                    child: const Text('Date'),
                  ),
                  TextButton(
                    onPressed: () async {
                      chosenTime = await showWheelTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 1, minute: 1),
                      );
                    },
                    child: const Text('Time'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      final now = DateTime.now();
      await tester.tap(find.byTooltip('Jump to today'));
      await tester.pump();
      if (!reduced) {
        final confirm = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Confirm'),
        );
        expect(confirm.onPressed, isNull);
      }
      await tester.pumpAndSettle();
      final wheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(wheels[0].scrollController!.selectedItem, now.month - 1);
      expect(wheels[1].scrollController!.selectedItem, now.day - 1);
      expect(wheels[2].scrollController!.selectedItem, now.year);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(chosen, DateUtils.dateOnly(now));
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      final currentTime = TimeOfDay.now();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.byTooltip('Jump to current time'));
      await tester.pumpAndSettle();
      final timeWheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(
        timeWheels[0].scrollController!.selectedItem % 24,
        currentTime.hour,
      );
      expect(
        timeWheels[1].scrollController!.selectedItem % 60,
        currentTime.minute,
      );
      expect(
        timeWheels[2].scrollController!.selectedItem,
        currentTime.hour >= 12 ? 1 : 0,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(chosenTime, currentTime);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Jump to today respects bounds; leap-day changes stay valid and cancel stays local',
    (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showWheelDatePicker(
                    context: context,
                    initialDate: DateTime(2024, 2, 29),
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2025, 3, 1),
                  );
                },
                child: const Text('Date'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      var wheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      wheels[2].scrollController!.jumpToItem(2023);
      await tester.pumpAndSettle();
      wheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(wheels[1].scrollController!.selectedItem, 27);
      await tester.tap(find.byTooltip('Jump to today'));
      await tester.pumpAndSettle();
      wheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(wheels[0].scrollController!.selectedItem, 2);
      expect(wheels[1].scrollController!.selectedItem, 0);
      expect(wheels[2].scrollController!.selectedItem, 2025);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
