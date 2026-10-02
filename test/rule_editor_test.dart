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
              body: ActivitySheet(initialTab: 1, conditionName: 'Budget limit'),
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
}
