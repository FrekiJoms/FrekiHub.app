import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';
import 'package:freki_hub/rule_language.dart';
import 'package:freki_hub/services.dart';

void main() {
  testWidgets('Logs stay separate and syntax opens as a full workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final data = await db.readAll();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      if (call.method == 'automationStatus') return {'background': false};
      if (call.method == 'automationEvents') return '[]';
      if (call.method == 'receiptNotificationsAllowed') return true;
      return null;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataProvider.overrideWithValue(AsyncData(data)),
        ],
        child: MaterialApp(
          theme: Design.theme(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: KeyboardOverlay(child: child!),
          ),
          home: Scaffold(body: SettingsScreen(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity logs'));
    await tester.pumpAndSettle();
    expect(find.byType(LogsSheet), findsOneWidget);
    expect(find.byType(SyntaxBuilderScreen), findsNothing);
    expect(find.text('Activity logging'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Syntax builder'));
    await tester.pumpAndSettle();
    expect(find.byType(SyntaxBuilderScreen), findsOneWidget);
    expect(tester.getSize(find.byType(SyntaxBuilderScreen)).height, 720);
    expect(find.byType(PanelContent), findsNothing);
    expect(find.byType(LogsSheet), findsNothing);
    expect(find.text('Activity logging'), findsNothing);
    expect(find.text('Conditions & automation'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SyntaxBuilderScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    messenger.setMockMethodCallHandler(NativeSession.channel, null);
    await db.close();
  });

  testWidgets(
    'Notification completion inserts valid schedules and repeat commands',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RuleCodeEditor(
              controller: controller,
              running: false,
              busy: false,
              run: () {},
              stop: () {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'target == notif');
      await tester.pump();
      await tester.tap(find.text('notifications'));
      await tester.pump();
      final schedules =
          RuleCompiler.compile(controller.text)['schedules'] as List;
      expect(schedules.single['count'], -1);
      await tester.enterText(
        find.byType(TextField),
        'target == notifications { schedule("test") { at("08:00"); repeat.co',
      );
      await tester.pump();
      expect(find.text('repeat.count'), findsOneWidget);
      await tester.tap(find.text('repeat.count'));
      await tester.pump();
      expect(controller.text, contains('repeat.count(10);'));
      await tester.enterText(
        find.byType(TextField),
        'target == notifications { schedule("test") { at("08:00"); repeat.we',
      );
      await tester.pump();
      await tester.tap(find.text('repeat.weekdays'));
      await tester.pump();
      expect(
        controller.text,
        contains('repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);'),
      );
      await tester.enterText(
        find.byType(TextField),
        'target == notifications { if (true) { notification.sh',
      );
      await tester.pump();
      await tester.tap(find.text('notification.show'));
      await tester.pump();
      expect(
        controller.text,
        contains('notification.show("Reminder", "Message");'),
      );
      expect(
        RuleCompiler.compile('${controller.text}\n} }')['needsNotifications'],
        true,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'Completion offers targets and Run/Stop changes the saved enabled flag',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RuleCodeEditor(
              controller: controller,
              running: false,
              busy: false,
              run: () {},
              stop: () {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'target == ');
      await tester.pump();
      expect(find.text('budget_page'), findsOneWidget);
      await tester.tap(find.text('budget_page'));
      await tester.pump();
      expect(controller.text, contains('target == budget_page {'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      const source =
          'target == budget_page { if (budget.expenses > 1000) { app.toast("Budget limit"); } }';
      await db.pref(
        'automation',
        jsonEncode({
          'rules': [
            {
              'id': 'budget-rule',
              'name': 'Budget limit',
              'lat': 0,
              'lng': 0,
              'radius': 150,
              'kind': 'Work',
              'else': 'continue',
              'enabled': false,
              'source': source,
              'program': RuleCompiler.compile(source),
            },
          ],
        }),
      );
      final data = await db.readAll();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        (call) async {
          if (call.method == 'automationStatus') return {'background': false};
          if (call.method == 'automationEvents') return '[]';
          if (call.method == 'receiptNotificationsAllowed') return true;
          return null;
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWithValue(AsyncData(data)),
          ],
          child: MaterialApp(
            theme: Design.theme(true),
            home: Scaffold(
              body: SyntaxBuilderScreen(conditionName: 'Budget limit'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Run rule'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Run rule'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Stop rule'), findsOneWidget);
      expect(
        jsonDecode((await db.readPreferences())['automation']!),
        isNot(contains('snapshot')),
      );
      expect(
        jsonDecode(
          (await db.readPreferences())['automation']!,
        )['rules'][0]['enabled'],
        true,
      );
      expect(find.text('Rule running'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop rule'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Run rule'), findsOneWidget);
      expect(
        jsonDecode(
          (await db.readPreferences())['automation']!,
        )['rules'][0]['enabled'],
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        null,
      );
      await db.close();
    },
  );

  testWidgets(
    'SyntaxBuilderScreen reveals focused code editor above keyboard overlay',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      const source =
          'target == app {\n  if (app.foreground == true) {\n    app.toast("Ready");\n  }\n}';
      await db.pref(
        'automation',
        jsonEncode({
          'rules': [
            {
              'id': 'r1',
              'name': 'Session toast',
              'enabled': false,
              'lat': 14.5995,
              'lng': 120.9842,
              'radius': 150,
              'else': 'stay',
              'kind': 'session',
              'source': source,
              'program': RuleCompiler.compile(source),
            },
          ],
        }),
      );
      final data = await db.readAll();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        (call) async {
          if (call.method == 'automationStatus') return {'background': false};
          if (call.method == 'automationEvents') return '[]';
          if (call.method == 'receiptNotificationsAllowed') return true;
          return null;
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWithValue(AsyncData(data)),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            builder: (context, child) => KeyboardOverlay(child: child!),
            home: const SyntaxBuilderScreen(conditionName: 'Session toast'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editorField = find.descendant(
        of: find.byType(RuleCodeEditor),
        matching: find.byType(TextField),
      );
      await tester.scrollUntilVisible(
        editorField,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(editorField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();

      final autoComplete = tester.widget<RawAutocomplete<Object>>(
        find.byWidgetPredicate((w) => w is RawAutocomplete),
      );
      expect(
        autoComplete.optionsViewOpenDirection,
        OptionsViewOpenDirection.up,
      );
      final editable = tester.state<EditableTextState>(
        find.descendant(of: editorField, matching: find.byType(EditableText)),
      );
      final caret = editable.renderEditable.getLocalRectForCaret(
        editable.textEditingValue.selection.extent,
      );
      final caretBottom = editable.renderEditable
          .localToGlobal(caret.bottomLeft)
          .dy;
      expect(caretBottom, lessThanOrEqualTo(760 - 320));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        null,
      );
      await db.close();
    },
  );

  testWidgets(
    'Lexical completion handles closed blocks, data.get quotes, templates, reference sheet, and deleting active rules',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: KeyboardOverlay(child: child!),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RuleCodeEditor(
                controller: controller,
                running: false,
                busy: false,
                settingFields: const ['settings.customFlag'],
                run: () {},
                stop: () {},
              ),
            ),
          ),
        ),
      );

      final field = find.descendant(
        of: find.byType(RuleCodeEditor),
        matching: find.byType(TextField),
      );

      // 1. All 10 targets offered after `target == ` (including #9 `notifications` and #10 `app` when scrolled).
      await tester.enterText(field, 'target == ');
      await tester.pump();
      expect(find.text('session_page'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pump();
      expect(find.text('notifications'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);

      // 2. After closing an `if { ... }` block, `else if` and `else` are offered.
      await tester.enterText(
        field,
        'target == session_page {\n  if (session.active) {\n    session.continue();\n  } el',
      );
      await tester.pump();
      expect(find.text('else if'), findsOneWidget);
      expect(find.text('else'), findsOneWidget);

      // 3. After closing an entire `target { ... }` block, `target` is offered again.
      await tester.enterText(
        field,
        'target == app {\n  if (true) {\n    log("Done");\n  }\n}\ntar',
      );
      await tester.pump();
      expect(find.text('target'), findsOneWidget);

      // 4. Inside `data.get("...`, field completion closes `") == ` cleanly.
      await tester.enterText(
        field,
        'target == app { if (data.get("settings.custom',
      );
      await tester.pump();
      expect(find.text('settings.customFlag'), findsOneWidget);
      await tester.tap(find.text('settings.customFlag'));
      await tester.pump();
      expect(controller.text, contains('data.get("settings.customFlag") == '));

      // 5. Templates drawer loads valid rule source; Reference drawer inserts item.
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(find.text('Starter templates'), findsOneWidget);
      await tester.tap(find.text('Weekday morning reminder'));
      await tester.pumpAndSettle();
      expect(RuleCompiler.compile(controller.text)['version'], 1);
      expect(find.textContaining('Syntax valid'), findsOneWidget);

      await tester.tap(find.text('Fields & actions'));
      await tester.pumpAndSettle();
      expect(find.text('Syntax reference'), findsOneWidget);
      await tester.tap(find.byTooltip('Close reference'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();

      // 6. Deleting an active running rule resets editing state and unlocks editor;
      //    toggling a visual rule into Structured syntax keeps editor editable.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      const runningSource =
          'target == app { if (app.foreground == true) { app.toast("Live"); } }';
      await db.pref(
        'automation',
        jsonEncode({
          'rules': [
            {
              'id': 'visual-1',
              'name': 'Campus',
              'lat': 14.6,
              'lng': 121.0,
              'radius': 150,
              'kind': 'Study',
              'else': 'clock_out',
              'enabled': true,
            },
            {
              'id': 'struct-1',
              'name': 'Live rule',
              'lat': 0,
              'lng': 0,
              'radius': 150,
              'kind': 'Work',
              'else': 'continue',
              'enabled': true,
              'source': runningSource,
              'program': RuleCompiler.compile(runningSource),
            },
          ],
        }),
      );
      final data = await db.readAll();
      addTearDown(db.close);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        (call) async {
          if (call.method == 'automationStatus') return {'background': true};
          if (call.method == 'automationEvents') return '[]';
          if (call.method == 'receiptNotificationsAllowed') return true;
          return null;
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWithValue(AsyncData(data)),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: KeyboardOverlay(child: child!),
            ),
            home: const SyntaxBuilderScreen(conditionName: 'Campus'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Campus is visual (`enabled: true`); switching to Structured syntax must stay editable.
      await tester.scrollUntilVisible(
        find.text('Structured syntax'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Structured syntax'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(RuleCodeEditor),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final editorWidget = tester.widget<RuleCodeEditor>(
        find.byType(RuleCodeEditor),
      );
      expect(editorWidget.running, isFalse);

      // Select running `Live rule`, then delete it and verify editor unlocks cleanly.
      await tester.scrollUntilVisible(
        find.text('Live rule'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Live rule'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(RuleCodeEditor),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<RuleCodeEditor>(find.byType(RuleCodeEditor)).running,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.byTooltip('Delete condition').last,
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Delete condition').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(RuleCodeEditor),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<RuleCodeEditor>(find.byType(RuleCodeEditor)).running,
        isFalse,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeSession.channel,
        null,
      );
    },
  );
}
