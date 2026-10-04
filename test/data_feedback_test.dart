import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets(
    'Committed session save, edit and deletion acknowledge once; cancel is quiet',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() => db.readAll());
      Session? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => panel(
                        context,
                        SessionForm(
                          data: AppData([], [], [], {}),
                          day: '2026-10-04',
                          session: selected,
                        ),
                      ),
                      child: const Text('Open session'),
                    ),
                    TextButton(
                      onPressed: () => deleteSession(context, ref, selected!),
                      child: const Text('Remove session'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Open session'));
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tester.tap(find.text('Save session'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(find.byType(TextField), 'First note');
      await save();
      expect(find.byType(SessionForm), findsNothing);
      expect(find.text('Session saved'), findsOneWidget);
      expect(find.byIcon(DataAction.saved.icon), findsOneWidget);
      final saved = await tester.runAsync(() => db.readAll());
      selected = saved!.sessions.single;
      expect(selected.note, 'First note');
      await open();
      await tester.enterText(find.byType(TextField), 'Edited note');
      await save();
      expect(find.text('Session saved'), findsNothing);
      expect(find.text('Session updated'), findsOneWidget);
      expect(find.byIcon(DataAction.updated.icon), findsOneWidget);
      final edited = await tester.runAsync(() => db.readAll());
      selected = edited!.sessions.single;
      expect(selected.note, 'Edited note');
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('top-toast-pill')), findsNothing);
      expect(
        (await tester.runAsync(() => db.readAll()))!.sessions,
        hasLength(1),
      );
      await tester.tap(find.text('Remove session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => db.readAll()))!.sessions, isEmpty);
      expect(find.text('Session deleted'), findsOneWidget);
      expect(find.byIcon(DataAction.deleted.icon), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Pending and failed writes never show success', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final write = Completer<void>();
    final operation = guarded(
      context,
      () => write.future,
      success: 'Transaction saved',
      successIcon: DataAction.saved.icon,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('top-toast-pill')), findsNothing);
    write.completeError(StateError('Write failed'));
    await operation;
    await tester.pumpAndSettle();
    expect(find.text('Transaction saved'), findsNothing);
    expect(find.text('Write failed'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
    expect(find.byIcon(DataAction.saved.icon), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
