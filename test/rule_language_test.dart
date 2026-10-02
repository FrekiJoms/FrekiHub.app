import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/rule_language.dart';
import 'package:freki_hub/data.dart';

void main() {
  test('Conditional system notifications combine location and time', () {
    final program = RuleCompiler.compile('''
target == notifications {
  if (time.between("08:00", "09:00") && location.inside() && weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])) {
    notification.show("At the office", "Clock in before 09:00");
  }
}
''');
    expect(program['needsLocation'], true);
    expect(program['needsNotifications'], true);
    expect(program['targets'][0]['branches'][0]['actions'][0], {
      'action': 'notification',
      'title': 'At the office',
      'body': 'Clock in before 09:00',
    });
    expect(
      () => RuleCompiler.compile(
        'target == app { if (true) { notification.show("A", "B"); } }',
      ),
      throwsFormatException,
    );
    expect(
      () => RuleCompiler.compile(
        'target == notifications { if (true) { notification.show("", "B"); } }',
      ),
      throwsFormatException,
    );
    expect(
      () => RuleCompiler.compile(
        'target == notifications { if (true) { notification.show("A"); } }',
      ),
      throwsFormatException,
    );
    expect(
      RuleCompiler.compile(
        'target == app { if (true) { app.toast("A"); } }',
      )['needsNotifications'],
      isNull,
    );
  });
  test('Selected weekday schedules support counted and unlimited repeats', () {
    final program = RuleCompiler.compile('''
target == notifications {
  schedule("workdays") {
    at("08:00");
    repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri", "Mon"]);
    repeat.count(10);
    notification.show("Work", "Clock in");
  }
  schedule("weekend") {
    repeat.forever();
    repeat.weekdays(["Sat", "Sun"]);
    at("09:00");
    notification.show("Weekend", "Take a break");
  }
}
''');
    final schedules = program['schedules'] as List;
    expect(schedules[0]['days'], [1, 2, 3, 4, 5]);
    expect(schedules[0]['daily'], false);
    expect(schedules[0]['count'], 10);
    expect(schedules[1]['days'], [6, 7]);
    expect(schedules[1]['count'], -1);
    for (final repeat in [
      'repeat.weekdays([]); repeat.forever();',
      'repeat.weekdays(["Thur"]); repeat.forever();',
      'repeat.weekdays([1]); repeat.forever();',
      'repeat.weekdays(["Mon"]);',
      'repeat.weekdays(["Mon"]); repeat.daily(); repeat.forever();',
      'repeat.daily(); repeat.weekdays(["Mon"]); repeat.forever();',
      'repeat.weekdays(["Mon"]); repeat.weekdays(["Tue"]); repeat.forever();',
      'repeat.weekdays(["Mon"]); repeat.forever(); repeat.count(2);',
    ]) {
      expect(
        () => RuleCompiler.compile(
          'target == notifications { schedule("bad") { at("08:00"); $repeat notification.show("A", "B"); } }',
        ),
        throwsFormatException,
        reason: repeat,
      );
    }
  });
  test('Compiles one-time, counted and unlimited notification schedules', () {
    final program = RuleCompiler.compile('''
target == notifications {
  schedule("once") { at("23:59"); notification.show("Reminder", "One time"); }
  schedule("ten_days") { notification.show("Work", "Clock in"); repeat.count(10); repeat.daily(); at("08:00"); }
  schedule("forever") { at("00:00"); repeat.daily(); repeat.forever(); notification.show("Daily", "Keep going"); }
}
target == app { if (notifications.schedule_count > 0 && notifications.exact_allowed == true) { log("Reminders active"); } }
''');
    final schedules = program['schedules'] as List;
    expect(schedules.length, 3);
    expect(schedules[0]['count'], 1);
    expect(schedules[0]['daily'], false);
    expect(schedules[1]['count'], 10);
    expect(schedules[1]['daily'], true);
    expect(schedules[2]['count'], -1);
    expect(program['needsLocation'], false);
  });
  test('Rejects ambiguous schedules, invalid times and repeat counts', () {
    for (final commands in [
      'at("24:00"); notification.show("A", "B");',
      'at("8:00"); notification.show("A", "B");',
      'at("08:00"); repeat.daily(); notification.show("A", "B");',
      'at("08:00"); repeat.count(2); notification.show("A", "B");',
      'at("08:00"); repeat.daily(); repeat.count(0); notification.show("A", "B");',
      'at("08:00"); repeat.daily(); repeat.count(1.5); notification.show("A", "B");',
      'at("08:00"); repeat.daily(); repeat.count(10001); notification.show("A", "B");',
      'at("08:00"); repeat.daily(); repeat.forever(); repeat.count(2); notification.show("A", "B");',
      'at("08:00"); at("09:00"); notification.show("A", "B");',
      'notification.show("A", "B");',
      'at("08:00"); notification.show("", "B");',
      'at("08:00"); notification.show("A", "B")',
    ]) {
      expect(
        () => RuleCompiler.compile(
          'target == notifications { schedule("test") { $commands } }',
        ),
        throwsFormatException,
        reason: commands,
      );
    }
    expect(
      () => RuleCompiler.compile(
        'target == app { schedule("test") { at("08:00"); notification.show("A", "B"); } }',
      ),
      throwsFormatException,
    );
    expect(
      () => RuleCompiler.compile(
        'target == notifications { schedule("same") { at("08:00"); notification.show("A", "B"); } schedule("same") { at("09:00"); notification.show("A", "B"); } }',
      ),
      throwsFormatException,
    );
  });
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
