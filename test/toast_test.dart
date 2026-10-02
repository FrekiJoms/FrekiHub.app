import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'Top pill replaces messages and dismisses (reduced motion: $reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: Design.theme(reducedMotion),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(
                padding: const EdgeInsets.only(top: 30),
                textScaler: const TextScaler.linear(2),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (c) {
                context = c;
                return const Scaffold();
              },
            ),
          ),
        );
        toast(context, 'First message');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        toast(
          context,
          'Could not save. Check your entries and try again. ' * 12,
          error: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('First message'), findsNothing);
        final pill = find.byKey(const ValueKey('top-toast-pill'));
        expect(pill, findsOneWidget);
        expect(tester.getTopLeft(pill).dy, closeTo(46, 1));
        expect(tester.getSize(pill).height, lessThanOrEqualTo(192));
        expect(tester.takeException(), isNull);
        // The old message's expiry must not remove its replacement.
        await tester.pump(const Duration(seconds: 3));
        expect(pill, findsOneWidget);
        await tester.tap(find.byTooltip('Dismiss message'));
        await tester.pumpAndSettle();
        expect(pill, findsNothing);
        toast(context, 'Auto dismiss', error: true);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle();
        expect(pill, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Invalid transaction stays editable and shows a top error pill', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: EntryForm(
              data: AppData([], [], [], {}),
              day: '2026-10-02',
              kind: 'expense',
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Save transaction'));
    await tester.tap(find.text('Save transaction'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('top-toast-pill')), findsOneWidget);
    expect(find.text('Enter a positive amount.'), findsOneWidget);
    expect(find.byType(EntryForm), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .decoration
          ?.errorText,
      isNull,
    );
    expect(await tester.runAsync(() => db.select(db.entries).get()), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Syntax validation retains line diagnostics in a top pill', (
    tester,
  ) async {
    final code = TextEditingController(text: 'target == invalid {}');
    addTearDown(code.dispose);
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: Design.theme(true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RuleCodeEditor(
              controller: code,
              running: false,
              busy: false,
              run: () => runs++,
              stop: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Validate syntax'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Line 1, column'), findsOneWidget);
    expect(find.byKey(const ValueKey('top-toast-pill')), findsOneWidget);
    await tester.tap(find.byTooltip('Run rule'));
    await tester.pumpAndSettle();
    expect(runs, 0);
    expect(find.byKey(const ValueKey('top-toast-pill')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
