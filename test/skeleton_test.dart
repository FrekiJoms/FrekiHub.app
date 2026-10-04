import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'Skeleton preserves geometry and interaction with reduced motion $reduced',
      (tester) async {
        var taps = 0;
        final semantics = tester.ensureSemantics();
        final loading = ValueNotifier(true);
        addTearDown(loading.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: loading,
                  builder: (_, pending, _) => SkeletonValue(
                    loading: pending,
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: const SizedBox(
                        width: 180,
                        height: 24,
                        child: Text('Loaded value'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final before = tester.getRect(find.byType(SkeletonValue));
        expect(find.bySemanticsLabel('Loading'), findsOneWidget);
        expect(find.bySemanticsLabel('Loaded value'), findsNothing);
        await tester.tapAt(before.center);
        expect(taps, 0);
        if (reduced) {
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
        } else {
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.binding.transientCallbackCount, greaterThan(0));
        }
        loading.value = false;
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(SkeletonValue)), before);
        expect(find.bySemanticsLabel('Loaded value'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.tapAt(before.center);
        expect(taps, 1);
        semantics.dispose();
      },
    );
  }

  testWidgets('Busy shared action retains its size and prevents repeat saves', (
    tester,
  ) async {
    final busy = ValueNotifier(false);
    addTearDown(busy.dispose);
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: Design.theme(false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: busy,
              builder: (_, saving, _) => AppButton(
                label: 'Save session',
                busy: saving,
                onPressed: () => saves++,
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(AppButton));
    busy.value = true;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AppButton)), rect);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<SkeletonValue>(find.byType(SkeletonValue)).loading,
      isTrue,
    );
    expect(find.text('Saving…'), findsNothing);
    await tester.tapAt(rect.center);
    expect(saves, 0);
    busy.value = false;
    await tester.pumpAndSettle();
    await tester.tapAt(rect.center);
    expect(saves, 1);
  });

  testWidgets(
    'Activity log loading preserves its heading and uses shared placeholders',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataProvider.overrideWithValue(const AsyncLoading<AppData>()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const Scaffold(body: LogsSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Activity logs'), findsOneWidget);
      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No activity yet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
