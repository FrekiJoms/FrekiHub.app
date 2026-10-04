import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
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
  });
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'Today synchronizes seconds and resume (reduced motion: $reducedMotion)',
      (tester) async {
        var now = DateTime(2026, 10, 4, 10, 20, 30, 250);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reducedMotion),
                child: Scaffold(
                  body: TodayScreen(
                    data: AppData([], [], [], {}),
                    clockNow: () => now,
                  ),
                ),
              ),
            ),
          ),
        );
        String digits() =>
            tester.widget<FlipClock>(find.byType(FlipClock)).value;
        Future<List<int>> pixels() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .ancestor(
                  of: find.byType(AnalogClock),
                  matching: find.byType(RepaintBoundary),
                )
                .first,
          );
          return (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              return (await image.toByteData())!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }))!;
        }

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(digits(), '10:20:30');
        expect(find.text('Current time · 10:20:30'), findsOneWidget);
        final initialPixels = await pixels();
        now = now.add(const Duration(milliseconds: 749));
        await tester.pump(const Duration(milliseconds: 149));
        expect(digits(), '10:20:30');
        now = now.add(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 1));
        expect(digits(), '10:20:31');
        expect(find.text('Current time · 10:20:31'), findsOneWidget);
        expect(await pixels(), isNot(orderedEquals(initialPixels)));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        now = DateTime(2026, 10, 5, 0, 1, 0, 125);
        await tester.pump(const Duration(seconds: 5));
        expect(digits(), '10:20:31');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(digits(), '00:01:00');
        expect(find.text('Current time · 00:01:00'), findsOneWidget);
        expect(find.text('Monday, 5 October'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Current time 00:01',
          ),
          findsOneWidget,
        );

        // A backward device-time adjustment is sampled at the next boundary.
        now = DateTime(2026, 10, 4, 9, 0);
        await tester.pump(const Duration(milliseconds: 875));
        expect(digits(), '09:00:00');
        expect(find.text('Sunday, 4 October'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Running elapsed time and small live time refresh from the same sample',
    (tester) async {
      var now = DateTime(2026, 10, 4, 13);
      final session = Session(
        id: 'running',
        day: dayKey(now),
        kind: 'Work',
        started: now
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        ended: null,
        note: '',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: TodayScreen(
                  data: AppData([session], [], [], {'clockFormat': '12'}),
                  clockNow: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      final display = tester.widget<FlipClock>(find.byType(FlipClock));
      expect(display.label, 'Elapsed time');
      expect(display.value, '00:01:00');
      expect(find.text('Current time · 01:00:00 PM'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<FlipClock>(find.byType(FlipClock)).value,
        '00:01:01',
      );
      final liveTime = find.text('Current time · 01:00:01 PM');
      expect(liveTime, findsOneWidget);
      expect(tester.widget<Text>(liveTime).style!.fontSize, 11);
      expect(
        tester.getBottomLeft(find.byType(FlipClock)).dy,
        lessThan(tester.getTopLeft(liveTime).dy),
      );
      expect(
        tester.getBottomLeft(liveTime).dy,
        lessThan(tester.getTopLeft(find.text('YOUR SESSION IS RUNNING')).dy),
      );
      expect(find.textContaining('Today’s total'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
