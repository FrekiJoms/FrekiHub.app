import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/startup.dart';

void main() {
  test('Preference updates preserve cached record tables', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final snapshots = StreamIterator(db.watchAll());
    addTearDown(() async {
      await snapshots.cancel();
      await db.close();
    });
    expect(await snapshots.moveNext(), isTrue);
    final first = snapshots.current;
    final update = snapshots.moveNext();
    await db.pref('theme', 'dark');
    expect(await update, isTrue);
    final second = snapshots.current;
    expect(second.prefs['theme'], 'dark');
    expect(identical(first.sessions, second.sessions), isTrue);
    expect(identical(first.entries, second.entries), isTrue);
    expect(identical(first.rules, second.rules), isTrue);
    final sessionUpdate = snapshots.moveNext();
    await db.clockIn('Focus');
    expect(await sessionUpdate, isTrue);
    expect(snapshots.current.sessions.single.note, 'Focus');
    expect(identical(second.entries, snapshots.current.entries), isTrue);
  });

  testWidgets(
    'Loader waits for readiness and intro does not replay on updates',
    (tester) async {
      Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));
      await tester.pumpWidget(
        app(const StartupLoading(stage: 'Opening your records')),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Opening your records'), findsOneWidget);
      await tester.pumpWidget(app(const StartupIntro(child: Text('Ready'))));
      await tester.pumpAndSettle();
      expect(find.text('Opening your records'), findsNothing);
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(StartupIntro),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        1,
      );
      await tester.pumpWidget(app(const StartupIntro(child: Text('Updated'))));
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(StartupIntro),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        1,
      );
      expect(find.text('Updated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reduced motion uses a static loader and immediate intro', (
    tester,
  ) async {
    Widget app(Widget child) => MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    );
    await tester.pumpWidget(
      app(const StartupLoading(stage: 'Preparing your space')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(const StartupIntro(child: Text('Ready'))));
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(StartupIntro),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
