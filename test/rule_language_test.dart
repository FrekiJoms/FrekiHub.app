import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/rule_language.dart';
import 'package:freki_hub/data.dart';

void main() {
  test('Compiles targets, precedence, arrays, else-if and scoped actions', () {
    final program = RuleCompiler.compile('''
// Workday timer
target == session_page {
  if (location.inside() && weekday.in(["Mon", "Fri"]) && time.between("22:00", "06:00")) {
    session.clock_in("Work");
    log("Clocked in");
  } else if (!session.active || location.outside()) {
    session.continue();
  } else { session.clock_out(); }
}
target == budget_page {
  if (budget.expenses >= 1000 && budget.currency == "PHP") { app.toast("Spending limit reached"); }
}
target == settings_page {
  if (data.get("settings.customPreference") == "yes") { settings.set_sound(false); }
}
''');
    expect(program['version'], 1);
    expect(program['needsLocation'], true);
    expect((program['targets'] as List).length, 3);
    expect(program['targets'][0]['branches'].length, 3);
    expect(program['targets'][1]['branches'][0]['condition']['op'], 'and');
  });
  test('Every registered target compiles and non-location rules need no GPS', () {
    for (final target in RuleCatalog.targets) {
      final result = RuleCompiler.compile(
        'target == $target { if (device.charging == true) { app.toast("Charging"); } }',
      );
      expect(result['needsLocation'], false);
    }
    final expense = RuleCompiler.compile(
      'target == budget_page { if (true) { budget.add_expense(1.50, "PHP", "Food", "Coffee"); } }',
    );
    expect(
      expense['targets'][0]['branches'][0]['actions'][0]['amount'],
      '1.50',
    );
  });
  test('Rejects incomplete syntax, unknown fields, unsafe actions and conflicting branches', () {
    for (final source in [
      'target == session_page { if (true) { session.clock_out() } }',
      'target == session_page { if (true) {',
      'target == missing_page { if (true) { log("X"); } }',
      'target == budget_page { if (true) { session.clock_in("Work"); } }',
      'target == session_page { if (true) { session.clock_in("Other"); } }',
      'target == session_page { if (unknown.field == 1) { log("X"); } }',
      'target == session_page { if (time.between("25:00", "08:00")) { log("X"); } }',
      'target == session_page { if (true) { session.clock_in("Work"); session.clock_out(); } }',
      'target == app { if (true) { eval("bad"); } }',
      'target == budget_page { if (true) { budget.add_expense(-1, "PHP", "Food", "X"); } }',
    ]) {
      expect(
        () => RuleCompiler.compile(source),
        throwsFormatException,
        reason: source,
      );
    }
  });
  test(
    'Diagnostics include a line/column and snapshots retain negative money',
    () {
      try {
        RuleCompiler.compile('target == app {\n if (true) { log("X") }\n}');
      } on FormatException catch (e) {
        expect(e.message, contains('Line 2, column'));
      }
      final day = dayKey(DateTime.now());
      final data = AppData(
        [],
        [
          Entry(
            id: 'expense',
            day: day,
            kind: 'expense',
            amount: 50,
            currency: 'PHP',
            category: 'Food',
            method: 'Cash',
            note: '',
            occurrence: null,
          ),
        ],
        [],
        {'customSetting': 'value'},
      );
      final snapshot = RuleCatalog.snapshot(data);
      expect(snapshot['budget.net'], -.5);
      expect(snapshot['settings.customSetting'], 'value');
      expect(snapshot['budget.transaction_count'], 1);
    },
  );
}
