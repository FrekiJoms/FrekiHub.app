import 'dart:convert';
import 'dart:math' as math;

import 'data.dart';

abstract final class RuleCatalog {
  static const booleanFields = {
    'session.active',
    'settings.sound',
    'activity_logs.enabled',
    'location.enabled',
    'notifications.purchases_enabled',
    'notifications.enabled',
    'notifications.exact_allowed',
    'device.charging',
    'device.connected',
    'app.foreground',
  };
  static bool numericField(String field) =>
      !field.startsWith('settings.') &&
      (field.endsWith('count') ||
          field.endsWith('seconds') ||
          [
            'budget.income',
            'budget.expenses',
            'budget.savings',
            'budget.net',
            'budget.last.amount',
            'device.battery',
            'device.volume',
            'location.lat',
            'location.lng',
            'location.accuracy',
            'location.sample_age_seconds',
            'budget.goal',
          ].contains(field));
  static const targets = [
    'session_page',
    'sessions_page',
    'budget_page',
    'calendar_page',
    'settings_page',
    'activity_logs',
    'device',
    'notifications',
    'app',
  ];
  static const fields = <String, String>{
    'session.active': 'A session is running',
    'session.kind': 'Running session type',
    'session.count': 'Total recorded sessions',
    'session.duration_seconds': 'Running duration in seconds',
    'session.today_seconds': 'Recorded time today',
    'session.note': 'Running session note',
    'budget.income': 'Income this month in display currency',
    'budget.expenses': 'Expenses this month',
    'budget.savings': 'Savings this month',
    'budget.net': 'Income minus expenses and savings',
    'budget.currency': 'Display currency',
    'budget.transaction_count': 'Recorded transaction count',
    'budget.rule_count': 'Budget planner rule count',
    'budget.last.amount': 'Last transaction amount',
    'budget.last.kind': 'Last transaction type',
    'budget.last.category': 'Last category',
    'budget.last.method': 'Last payment method',
    'budget.last.note': 'Last transaction note',
    'calendar.selected_date': 'Selected calendar date (yyyy-MM-dd)',
    'calendar.view': 'year, month, week or day',
    'calendar.today': 'Today (yyyy-MM-dd)',
    'settings.theme': 'light, dark or system',
    'settings.sound': 'Sound effects enabled',
    'activity_logs.enabled': 'Activity logging enabled',
    'activity_logs.count': 'Saved activity count',
    'activity_logs.last.action': 'Last activity action',
    'activity_logs.last.title': 'Last activity title',
    'location.enabled': 'Location conditions enabled',
    'location.name': 'Last sampled place name',
    'notifications.purchases_enabled': 'Purchase detection enabled',
    'notifications.enabled': 'Android notifications permitted',
    'notifications.exact_allowed': 'Precise reminder scheduling permitted',
    'notifications.schedule_count': 'Active notification schedules',
    'notifications.reminder_sound': 'Reminder sound URI or silent',
    'notifications.transaction_sound': 'Saved-transaction sound URI or silent',
    'notifications.session_sound': 'Running-session sound URI or silent',
    'device.battery': 'Battery percentage',
    'device.charging': 'Device is charging',
    'device.connected': 'A network interface is connected',
    'device.orientation': 'portrait or landscape',
    'device.volume': 'Media volume percentage',
    'device.ringer_mode': 'normal, vibrate or silent',
    'location.lat': 'Last sampled latitude',
    'location.lng': 'Last sampled longitude',
    'location.accuracy': 'Sample accuracy in metres',
    'location.sample_age_seconds': 'Age of the last location sample',
    'budget.goal': 'Savings goal in display currency',
    'app.page': 'Current app page',
    'app.foreground': 'App is visible',
  };
  static Map<String, dynamic> snapshot(AppData data) {
    final now = DateTime.now(), current = data.running;
    final month = dayKey(now).substring(0, 7);
    Entry? last;
    for (final entry in data.entries) {
      if (last == null || entry.day.compareTo(last.day) >= 0) last = entry;
    }
    double major(int amount) =>
        amount / math.pow(10, currencyDigits[data.currency] ?? 2);
    final income = data.total('income', month: month),
        expenses = data.total('expense', month: month),
        savings = data.total('savings', month: month);
    return {
      '_sampleTime': now.millisecondsSinceEpoch,
      '_runningId': current?.id ?? '',
      '_day': dayKey(now),
      'session.active': current != null,
      'session.kind': current?.kind ?? '',
      'session.count': data.sessions.length,
      'session.note': current?.note ?? '',
      'session.today_seconds': data.sessions
          .where((s) => s.day == dayKey(now))
          .fold<int>(
            0,
            (total, s) =>
                total +
                ((s.ended ?? now.millisecondsSinceEpoch) - s.started) ~/ 1000,
          ),
      'budget.income': major(income),
      'budget.expenses': major(expenses),
      'budget.savings': major(savings),
      'budget.net': major(income - expenses - savings),
      'budget.currency': data.currency,
      'budget.transaction_count': data.entries.length,
      'budget.rule_count': data.rules.length,
      'budget.goal': major(
        int.tryParse(data.prefs['savingsGoal:${data.currency}'] ?? '') ?? 0,
      ),
      'budget.last.amount': last == null
          ? 0
          : last.amount / math.pow(10, currencyDigits[last.currency] ?? 2),
      'budget.last.kind': last?.kind ?? '',
      'budget.last.category': last?.category ?? '',
      'budget.last.method': last?.method ?? '',
      'budget.last.note': last?.note ?? '',
      'calendar.today': dayKey(now),
      'calendar.selected_date': data.prefs['calendarSelected'] ?? dayKey(now),
      'calendar.view': data.prefs['calendarView'] ?? 'month',
      'settings.theme': data.prefs['theme'] ?? 'system',
      'settings.sound': data.prefs['sound'] == 'true',
      'activity_logs.enabled': data.prefs['activityLogging'] == 'true',
      'activity_logs.count':
          int.tryParse(data.prefs['activityCount'] ?? '') ?? 0,
      'activity_logs.last.action': data.prefs['lastActivityAction'] ?? '',
      'activity_logs.last.title': data.prefs['lastActivityTitle'] ?? '',
      'location.enabled': data.prefs['locationEnabled'] == 'true',
      'location.name': data.prefs['locationName'] ?? '',
      'notifications.purchases_enabled':
          data.prefs['purchaseScanning'] == 'true',
      'app.page': data.prefs['currentPage'] ?? 'session_page',
      'app.foreground': true,
      for (final pref in data.prefs.entries.where(
        (p) =>
            p.key != 'automation' &&
            !p.key.startsWith('purchaseNotice:') &&
            !p.key.startsWith('ruleToast:'),
      ))
        'settings.${pref.key}': pref.value,
    }..addAll({
      'settings.theme': data.prefs['theme'] ?? 'system',
      'settings.sound': data.prefs['sound'] == 'true',
    });
  }
}

/// A bounded, declarative language. Source is parsed into data, never evaluated as JavaScript.
class RuleCompiler {
  static final _cache = <String, Map<String, dynamic>>{};
  static Map<String, dynamic> compile(String source) {
    if (_cache.containsKey(source)) return _cache[source]!;
    final program = _Parser(source).parse();
    if (_cache.length >= 100) _cache.remove(_cache.keys.first);
    return _cache[source] = program;
  }

  static String visual({required String kind, required String exit}) =>
      'target == session_page {\n'
      '  if (location.inside()) {\n'
      '    session.clock_in(${jsonEncode(kind)});\n'
      '  } else {\n'
      '    session.${exit == 'clock_out' ? 'clock_out' : 'continue'}();\n'
      '  }\n'
      '}';
}

class _Token {
  final String value;
  final int offset;
  const _Token(this.value, this.offset);
}

class _Parser {
  final String source;
  final tokens = <_Token>[];
  int cursor = 0, depth = 0, nodes = 0;
  _Parser(this.source) {
    if (source.length > 8192) throw const FormatException('Rule exceeds 8 KB.');
    final pattern = RegExp(
      r'\s+|//[^\n]*|"(?:\\.|[^"\\])*"|==|!=|>=|<=|&&|\|\||[{}\[\](),;!<>]|-?\d+(?:\.\d+)?|[A-Za-z_][A-Za-z_0-9.]*',
    );
    int offset = 0;
    while (offset < source.length) {
      final match = pattern.matchAsPrefix(source, offset);
      if (match == null) fail('Unexpected character', offset);
      final value = match.group(0)!;
      if (value.trim().isNotEmpty && !value.startsWith('//')) {
        tokens.add(_Token(value, offset));
      }
      offset = match.end;
    }
    tokens.add(_Token('<end>', source.length));
  }
  String get next => cursor < tokens.length ? tokens[cursor].value : '<end>';
  Never fail(String message, [int? at]) {
    final prefix = source.substring(
      0,
      at ?? (cursor < tokens.length ? tokens[cursor].offset : source.length),
    );
    final line = '\n'.allMatches(prefix).length + 1;
    final column = prefix.length - prefix.lastIndexOf('\n');
    throw FormatException('Line $line, column $column: $message.');
  }

  bool take(String value) {
    if (next != value) return false;
    cursor++;
    return true;
  }

  void need(String value) {
    if (!take(value)) fail('Expected "$value", found "$next"');
  }

  String string() {
    if (!next.startsWith('"')) fail('Expected a double-quoted string');
    final value = next;
    cursor++;
    try {
      return jsonDecode(value) as String;
    } catch (_) {
      fail('Invalid string escape');
    }
  }

  Map<String, dynamic> parse() {
    final targets = <Map<String, dynamic>>[];
    final schedules = <Map<String, dynamic>>[];
    int blocks = 0;
    while (next != '<end>') {
      need('target');
      need('==');
      final target = next;
      cursor++;
      if (!RuleCatalog.targets.contains(target)) {
        fail('Unknown target "$target"');
      }
      need('{');
      if (next == 'schedule') {
        if (target != 'notifications') {
          fail('Schedules require the notifications target');
        }
        while (take('schedule')) {
          final value = schedule();
          if (schedules.any((s) => s['name'] == value['name'])) {
            fail('Schedule names must be unique within a rule');
          }
          schedules.add(value);
          if (schedules.length > 16) fail('Use at most sixteen schedules');
        }
        need('}');
        if (++blocks > 16) fail('Use at most sixteen target blocks');
        continue;
      }
      need('if');
      final branches = <Map<String, dynamic>>[];
      branches.add(branch(target));
      while (take('else')) {
        if (take('if')) {
          branches.add(branch(target));
        } else {
          branches.add({
            'condition': {'op': 'literal', 'value': true},
            'actions': actions(target),
          });
          break;
        }
      }
      need('}');
      targets.add({'target': target, 'branches': branches});
      if (++blocks > 16) fail('Use at most sixteen target blocks');
    }
    if (blocks == 0) fail('Add a target block');
    return {
      'version': 1,
      'targets': targets,
      if (schedules.isNotEmpty) 'schedules': schedules,
      'needsLocation': tokens.any(
        (t) => ['location.inside', 'location.outside'].contains(t.value),
      ),
    };
  }

  Map<String, dynamic> schedule() {
    need('(');
    final name = string();
    if (!RegExp(r'^[A-Za-z_][A-Za-z_0-9-]{0,63}$').hasMatch(name)) {
      fail('Schedule name must be a unique identifier of 1–64 characters');
    }
    need(')');
    need('{');
    String? time, title, body;
    bool daily = false;
    List<int>? days;
    int? count;
    final seen = <String>{};
    while (!take('}')) {
      final command = next;
      cursor++;
      if (!seen.add(command)) fail('Duplicate schedule command "$command"');
      need('(');
      switch (command) {
        case 'at':
          time = string();
          if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
            fail('Use a valid 24-hour time such as "08:00"');
          }
        case 'repeat.daily':
          if (days != null) fail('Choose daily or weekdays, not both');
          daily = true;
        case 'repeat.weekdays':
          if (daily) fail('Choose daily or weekdays, not both');
          days = weekdays();
        case 'repeat.forever':
          if (count != null) fail('Choose count or forever, not both');
          count = -1;
        case 'repeat.count':
          if (count != null) fail('Choose count or forever, not both');
          count = int.tryParse(next);
          if (count == null || count < 1 || count > 10000) {
            fail('Repeat count must be an integer from 1 to 10,000');
          }
          cursor++;
        case 'notification.show':
          title = string();
          need(',');
          body = string();
          if (title.trim().isEmpty ||
              title.length > 100 ||
              body.trim().isEmpty ||
              body.length > 500) {
            fail(
              'Use a title of 1–100 characters and body of 1–500 characters',
            );
          }
        default:
          fail('Unknown schedule command "$command"');
      }
      need(')');
      need(';');
    }
    if (time == null || title == null) {
      fail('A schedule needs at() and notification.show()');
    }
    if ((daily || days != null) && count == null) {
      fail('Repeats need repeat.count() or repeat.forever()');
    }
    if (!daily && days == null && count != null) {
      fail('Repeating requires repeat.daily() or repeat.weekdays()');
    }
    return {
      'name': name,
      'time': time,
      'daily': daily,
      'days': ?days,
      'count': count ?? 1,
      'title': title,
      'body': body,
    };
  }

  List<int> weekdays() {
    need('[');
    final days = <int>{};
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    do {
      final day = string();
      if (!names.contains(day)) {
        fail('Weekday must be Mon, Tue, Wed, Thu, Fri, Sat or Sun');
      }
      days.add(names.indexOf(day) + 1);
    } while (take(','));
    need(']');
    return days.toList();
  }

  Map<String, dynamic> branch(String target) {
    need('(');
    final condition = expression();
    need(')');
    return {'condition': condition, 'actions': actions(target)};
  }

  Map<String, dynamic> node(String op, Map<String, dynamic> fields) {
    if (++nodes > 128) fail('Condition is too complex');
    final result = {'op': op, ...fields};
    int treeDepth(Map<String, dynamic> value) =>
        1 +
        value.values.whereType<Map<String, dynamic>>().fold<int>(
          0,
          (d, child) => math.max(d, treeDepth(child)),
        );
    if (treeDepth(result) > 16) fail('Condition nesting exceeds 16 levels');
    return result;
  }

  Map<String, dynamic> expression() {
    var left = and();
    while (take('||')) {
      left = node('or', {'left': left, 'right': and()});
    }
    return left;
  }

  Map<String, dynamic> and() {
    var left = primary();
    while (take('&&')) {
      left = node('and', {'left': left, 'right': primary()});
    }
    return left;
  }

  Map<String, dynamic> primary() {
    if (++depth > 16) fail('Use at most 16 nested conditions');
    try {
      if (take('!')) return node('not', {'value': primary()});
      if (take('(')) {
        final value = expression();
        need(')');
        return value;
      }
      if (take('true')) return node('literal', {'value': true});
      if (take('false')) return node('literal', {'value': false});
      final function = next;
      cursor++;
      if (RuleCatalog.fields.containsKey(function) &&
          function != 'session.active') {
        return comparison(function);
      }
      if (function == 'data.get') {
        need('(');
        final field = string();
        need(')');
        if (!RuleCatalog.fields.containsKey(field) &&
            !field.startsWith('settings.')) {
          fail('Unknown data field "$field"');
        }
        return comparison(field);
      }
      if (function == 'session.active') {
        if (['==', '!='].contains(next)) return comparison(function);
        return node('active', {'value': true});
      }
      need('(');
      if (['location.inside', 'location.outside'].contains(function)) {
        need(')');
        return node(function == 'location.inside' ? 'inside' : 'outside', {});
      }
      if (function == 'time.between') {
        final from = string();
        need(',');
        final until = string();
        need(')');
        int minute(String s) {
          if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(s)) {
            fail('Time must use 24-hour HH:mm');
          }
          final parts = s.split(':');
          return int.parse(parts[0]) * 60 + int.parse(parts[1]);
        }

        final start = minute(from), end = minute(until);
        if (start == end) fail('Time boundaries must differ');
        return node('time', {'from': start, 'until': end});
      }
      if (function == 'weekday.in') {
        final days = weekdays();
        need(')');
        return node('weekday', {'days': days});
      }
      fail('Unknown condition "$function"');
    } finally {
      depth--;
    }
  }

  Map<String, dynamic> comparison(String field) {
    final operator = next;
    if (!['==', '!=', '>', '<', '>=', '<='].contains(operator)) {
      fail('Add a comparison operator after $field');
    }
    cursor++;
    dynamic value;
    if (next.startsWith('"')) {
      value = string();
    } else if (['true', 'false'].contains(next)) {
      value = next == 'true';
      cursor++;
    } else {
      value = num.tryParse(next);
      if (value == null || !(value as num).isFinite) {
        fail('Expected a string, boolean or number');
      }
      cursor++;
    }
    if (['>', '<', '>=', '<='].contains(operator) && value is! num) {
      fail('Ordering comparisons require a number');
    }
    if (RuleCatalog.booleanFields.contains(field) && value is! bool) {
      fail('$field requires true or false');
    }
    if (RuleCatalog.numericField(field) && value is! num) {
      fail('$field requires a number');
    }
    if (!RuleCatalog.booleanFields.contains(field) &&
        !RuleCatalog.numericField(field) &&
        value is! String) {
      fail('$field requires a double-quoted string');
    }
    return node('compare', {
      'field': field,
      'operator': operator,
      'value': value,
    });
  }

  List<Map<String, dynamic>> actions(String target) {
    need('{');
    final result = <Map<String, dynamic>>[];
    int sessionActions = 0;
    while (!take('}')) {
      final action = next;
      cursor++;
      need('(');
      Map<String, dynamic> value;
      if (action == 'log') {
        final message = string();
        if (message.trim().isEmpty || message.length > 200) {
          fail('Log message must contain 1–200 characters');
        }
        value = {'action': 'log', 'message': message};
      } else if (action == 'app.toast') {
        final message = string();
        if (message.trim().isEmpty || message.length > 200) {
          fail('Toast must contain 1–200 characters');
        }
        value = {'action': 'toast', 'message': message};
      } else if (target == 'settings_page' && action == 'settings.set_theme') {
        final theme = string();
        if (!['light', 'dark', 'system'].contains(theme)) {
          fail('Theme must be light, dark or system');
        }
        value = {'action': 'setting', 'key': 'theme', 'value': theme};
      } else if (target == 'settings_page' && action == 'settings.set_sound') {
        if (!['true', 'false'].contains(next)) {
          fail('Sound requires true or false');
        }
        final enabled = next;
        cursor++;
        value = {'action': 'setting', 'key': 'sound', 'value': enabled};
      } else if (target == 'budget_page' && action == 'budget.add_expense') {
        final amount = num.tryParse(next);
        if (amount == null ||
            !amount.isFinite ||
            amount <= 0 ||
            amount > 1000000000) {
          fail('Expense amount must be positive and at most 1 billion');
        }
        final amountText = next;
        cursor++;
        need(',');
        final currency = string();
        need(',');
        final category = string();
        need(',');
        final note = string();
        if (!currencyDigits.containsKey(currency)) fail('Unknown currency');
        try {
          if (parseMoney(amountText, currency) <= 0) {
            fail('Expense is too small');
          }
        } on FormatException {
          fail('Invalid currency precision');
        }
        if (category.trim().isEmpty ||
            category.length > 80 ||
            note.length > 200) {
          fail('Invalid category or note');
        }
        value = {
          'action': 'expense',
          'amount': amountText,
          'currency': currency,
          'category': category,
          'note': note,
        };
      } else if (target == 'session_page' && action == 'session.clock_in') {
        final kind = string();
        if (!['OJT', 'Work', 'Study', 'Personal'].contains(kind)) {
          fail('Unknown session type "$kind"');
        }
        value = {'action': 'clock_in', 'kind': kind};
        sessionActions++;
      } else if (target == 'session_page' &&
          ['session.clock_out', 'session.continue'].contains(action)) {
        value = {
          'action': action == 'session.clock_out' ? 'clock_out' : 'continue',
        };
        sessionActions++;
      } else {
        fail('Unknown action "$action" for $target');
      }
      need(')');
      need(';');
      result.add(value);
      if (sessionActions > 1) fail('Use one session action per branch');
      if (result.length > 8) fail('Use at most eight actions per branch');
    }
    if (result.isEmpty) {
      fail('Add an action; use session.continue() to keep running');
    }
    return result;
  }
}
