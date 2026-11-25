import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/rule_language.dart';
import 'package:freki_hub/data.dart';

void main() {
  test('Queue, timer and invalid-projection diagnostics expose typed fields', () {
    for (final field in [
      'session.timer_available',
      'location.logging_paused',
    ]) {
      expect(RuleCatalog.fields, contains(field));
      RuleCompiler.compile(
        'target == app { if (data.get("$field") == false) { log("Diagnostic"); } }',
      );
      expect(
        () => RuleCompiler.compile(
          'target == app { if (data.get("$field") == "false") { log("Wrong type"); } }',
        ),
        throwsFormatException,
      );
    }
    for (final field in [
      'activity_logs.pending_count',
      'budget.invalid_projection_count',
    ]) {
      expect(RuleCatalog.fields, contains(field));
      RuleCompiler.compile(
        'target == app { if (data.get("$field") > 0) { log("Pending"); } }',
      );
      expect(
        () => RuleCompiler.compile(
          'target == app { if (data.get("$field") == "many") { log("Wrong type"); } }',
        ),
        throwsFormatException,
      );
    }
  });
  test('Foreground Map location fields have typed completion and snapshots', () {
    expect(RuleCatalog.fields, contains('map.current_location_visible'));
    expect(RuleCatalog.numericField('map.current_location_accuracy'), isTrue);
    expect(
      RuleCatalog.numericField('map.current_location_sample_epoch'),
      isTrue,
    );
    RuleCompiler.compile(
      'target == map_page { if (data.get("map.current_location_visible") == true && data.get("map.current_location_sample_epoch") > 0) { app.toast("You are here"); } }',
    );
    expect(
      () => RuleCompiler.compile(
        'target == map_page { if (data.get("map.current_location_visible") == "yes") { app.toast("Invalid"); } }',
      ),
      throwsFormatException,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    AppData data(int time) => AppData([], [], [], {
      'mapContext':
          '{"map.current_location_visible":true,"map.current_location_sample_epoch":$time}',
    });
    expect(
      RuleCatalog.snapshot(data(now))['map.current_location_visible'],
      isTrue,
    );
    expect(
      RuleCatalog.snapshot(data(now - 120001))['map.current_location_visible'],
      isFalse,
    );
    expect(RuleCatalog.fields, contains('map.cluster_count'));
    expect(RuleCatalog.fields, contains('map.muted'));
    expect(RuleCatalog.fields, contains('location.dwell_minutes'));
    expect(RuleCatalog.numericField('map.cluster_count'), isTrue);
    expect(RuleCatalog.numericField('location.dwell_minutes'), isTrue);
    expect(RuleCatalog.booleanFields, contains('map.muted'));
    RuleCompiler.compile(
      'target == map_page { if (data.get("map.cluster_count") > 0 && data.get("map.muted") == true) { log("Clustered"); } }',
    );
    RuleCompiler.compile(
      'target == notifications { if (location.inside() && data.get("location.dwell_minutes") >= 30) { notification.show("Stayed 30m", "Prompting after dwell"); } }',
    );
    expect(
      RuleCatalog.snapshot(
        AppData([], [], [], {'locationDwellMinutes': '35'}),
      )['location.dwell_minutes'],
      35,
    );
  });

  test('Overlay permission is a discoverable boolean native field', () {
    expect(RuleCatalog.fields, contains('device.overlay_allowed'));
    expect(RuleCatalog.booleanFields, contains('device.overlay_allowed'));
    expect(
      RuleCompiler.compile(
        'target == app { if (data.get("device.overlay_allowed") == true) { app.toast("Overlay ready"); } }',
      )['needsLocation'],
      false,
    );
    expect(
      () => RuleCompiler.compile(
        'target == app { if (data.get("device.overlay_allowed") == "yes") { app.toast("Invalid"); } }',
      ),
      throwsFormatException,
    );
  });
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
  test('Diagnostics include a line/column and snapshots retain negative money', () {
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
    expect(snapshot['budget.balance'], -.5);
    expect(snapshot['settings.customSetting'], 'value');
    expect(snapshot['budget.transaction_count'], 1);
    final previousMonth = dayKey(
      DateTime(DateTime.now().year, DateTime.now().month - 1),
    );
    final history = AppData(
      [],
      [
        ...data.entries,
        data.entries.first.copyWith(
          id: 'prior-income',
          day: previousMonth,
          kind: 'income',
          amount: 300,
        ),
        data.entries.first.copyWith(
          id: 'other-currency',
          kind: 'income',
          currency: 'USD',
          amount: 99900,
        ),
        data.entries.first.copyWith(id: 'saved', kind: 'savings', amount: 100),
      ],
      [],
      data.prefs,
    );
    expect(history.balance, 150);
    expect(RuleCatalog.snapshot(history)['budget.balance'], 1.5);
    expect(RuleCatalog.snapshot(history)['budget.net'], -1.5);
    expect(RuleCatalog.fields, contains('budget.balance'));
    expect(
      () => RuleCompiler.compile(
        'target == app { if (budget.balance < 100) { app.toast("Low balance"); } }',
      ),
      returnsNormally,
    );
    expect(
      () => RuleCompiler.compile(
        'target == app { if (budget.balance == "100") { log("Wrong type"); } }',
      ),
      throwsFormatException,
    );
  });

  test('notifications.sms_enabled exposes boolean metadata, snapshot state and type validation', () {
    expect(RuleCatalog.fields, contains('notifications.sms_enabled'));
    expect(RuleCatalog.booleanFields, contains('notifications.sms_enabled'));
    expect(
      RuleCatalog.snapshot(
        AppData([], [], [], {}),
      )['notifications.sms_enabled'],
      false,
    );
    expect(
      RuleCatalog.snapshot(
        AppData([], [], [], {'smsScanning': 'true'}),
      )['notifications.sms_enabled'],
      true,
    );
    expect(
      RuleCatalog.snapshot(
        AppData([], [], [], {'smsScanning': 'false'}),
      )['notifications.sms_enabled'],
      false,
    );
    expect(
      () => RuleCompiler.compile(
        'target == notifications { if (notifications.sms_enabled == true) { log("SMS enabled"); } }',
      ),
      returnsNormally,
    );
    expect(
      () => RuleCompiler.compile(
        'target == notifications { if (notifications.sms_enabled == "true") { log("Wrong type"); } }',
      ),
      throwsFormatException,
    );
  });

  test('Snapshot includes session.duration_seconds, immutable AST cache, usesLocation, and mixed notifications blocks', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final idleSnap = RuleCatalog.snapshot(AppData([], [], [], {}));
    expect(idleSnap['session.duration_seconds'], 0);
    final activeSnap = RuleCatalog.snapshot(
      AppData(
        [
          Session(
            id: 's1',
            day: dayKey(DateTime.now()),
            kind: 'Work',
            started: now - 125000,
            ended: null,
            note: 'Coding',
          ),
        ],
        [],
        [],
        {},
      ),
    );
    expect(activeSnap['session.duration_seconds'], greaterThanOrEqualTo(124));
    expect(RuleCatalog.fieldType('session.active'), 'bool');
    expect(RuleCatalog.fieldType('budget.expenses'), 'number');
    expect(RuleCatalog.fieldType('session.kind'), 'string');

    // Compiler cache returns immutable maps/lists.
    final compiled = RuleCompiler.compile(
      'target == app { if (true) { app.toast("Immutable"); } }',
    );
    expect(() => compiled['version'] = 2, throwsUnsupportedError);
    expect(() => (compiled['targets'] as List).clear(), throwsUnsupportedError);

    // usesLocation ignores comments and string literals.
    expect(
      RuleCompiler.usesLocation(
        '// location.inside()\ntarget == app { if (true) { log("location.outside()"); } }',
      ),
      isFalse,
    );
    expect(
      RuleCompiler.usesLocation(
        'target == session_page { if (location.inside()) { session.clock_in("Work"); } }',
      ),
      isTrue,
    );

    // Notifications block supports both schedule and conditional if chain.
    final mixed = RuleCompiler.compile('''
target == notifications {
  schedule("morning") {
    at("08:00");
    notification.show("Morning", "Start");
  }
  if (location.inside()) {
    notification.show("Arrived", "At workplace");
  }
}
''');
    expect((mixed['schedules'] as List).length, 1);
    expect((mixed['targets'] as List).length, 1);
    expect(mixed['needsNotifications'], isTrue);
    expect(mixed['needsLocation'], isTrue);

    // Unterminated strings, single '=', and duplicate top-level if inside one block fail cleanly.
    for (final invalid in [
      'target = app { if (true) { log("A"); } }',
      'target == app { if (budget.expenses = 10) { log("A"); } }',
      'target == app { if (true) { log("unterminated); } }',
      'target == app { if (true) { log("A"); } if (false) { log("B"); } }',
    ]) {
      expect(
        () => RuleCompiler.compile(invalid),
        throwsFormatException,
        reason: invalid,
      );
    }
  });
}
