import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
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

  Future<AppDatabase> openHome(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final session = await tester.runAsync(() => db.clockIn('Original'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: TodayScreen(data: AppData([session!], [], [], {})),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    return db;
  }

  Future<String> savedNote(WidgetTester tester, AppDatabase db) async =>
      (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return db.readAll();
      }))!.sessions.single.note;

  testWidgets(
    'Typing is coalesced; selection does not save; blur flushes latest draft',
    (tester) async {
      final db = await openHome(tester);
      final observed = <String>[];
      final subscription = db
          .select(db.sessions)
          .watch()
          .listen((rows) => observed.add(rows.single.note));
      addTearDown(subscription.cancel);
      await tester.enterText(find.byType(TextField), 'A');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'A finished note');
      await tester.pump(const Duration(milliseconds: 200));
      expect(await savedNote(tester, db), 'Original');
      await tester.pump(const Duration(milliseconds: 250));
      expect(await savedNote(tester, db), 'A finished note');
      expect(observed.where((text) => text == 'A'), isEmpty);
      final count = observed.length;
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(await savedNote(tester, db), 'A finished note');
      expect(observed.length, count);
      await tester.enterText(find.byType(TextField), 'Flush on blur');
      field.focusNode!.unfocus();
      await tester.pump();
      expect(await savedNote(tester, db), 'Flush on blur');
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'IME composing stays local; composition completion and leaving Home save',
    (tester) async {
      final db = await openHome(tester);
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.value = const TextEditingValue(
        text: 'Compose',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 0, end: 7),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(await savedNote(tester, db), 'Original');
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      await tester.pump(const Duration(milliseconds: 410));
      expect(await savedNote(tester, db), 'Compose');
      await tester.enterText(find.byType(TextField), 'Leaving Home');
      await tester.pumpWidget(const SizedBox());
      expect(await savedNote(tester, db), 'Leaving Home');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Confirming clock-out saves the latest draft before the debounce',
    (tester) async {
      final db = await openHome(tester);
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          '  Final draft  ';
      await tester.ensureVisible(find.text('Clock out'));
      await tester.tap(find.text('Clock out'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(await savedNote(tester, db), 'Original');
      await tester.tap(find.text('End session'));
      await tester.pump();
      final data = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return db.readAll();
      });
      expect(data!.sessions.single.note, 'Final draft');
      expect(data.running, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      expect(await savedNote(tester, db), 'Final draft');
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Leaving Home flushes the first draft without a previous autosave',
    (tester) async {
      final db = await openHome(tester);
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          'First draft';
      await tester.pumpWidget(const SizedBox());
      expect(await savedNote(tester, db), 'First draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pending note cannot change a session already ended elsewhere', (
    tester,
  ) async {
    final db = await openHome(tester);
    final session = (await tester.runAsync(db.readAll))!.running!;
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    await tester.runAsync(() => db.clockOut(session.id));
    await tester.pump(const Duration(milliseconds: 410));
    expect(await savedNote(tester, db), 'Original');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
