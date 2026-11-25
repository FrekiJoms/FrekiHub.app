part of 'screens.dart';

class _CodeHint {
  final String label, detail, source, badge;
  final int cursor;
  const _CodeHint(
    this.label,
    this.detail,
    this.source,
    this.cursor, {
    this.badge = '',
  });
}

enum _EditorBlockKind { target, schedule, branch, other }

class _EditorBlock {
  final _EditorBlockKind kind;
  final String? target;
  final int startOffset;
  _EditorBlockKind? lastClosedChild;
  _EditorBlock(this.kind, {this.target, required this.startOffset});
}

enum _EditorParenKind { condition, call, group }

class _EditorParen {
  final _EditorParenKind kind;
  final String? callee;
  const _EditorParen(this.kind, {this.callee});
}

class _RuleTemplate {
  final String title, subtitle, badge, source;
  final IconData icon;
  const _RuleTemplate({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.source,
  });
}

const _ruleTemplates = <_RuleTemplate>[
  _RuleTemplate(
    title: 'Workday place clock-in & out',
    subtitle: 'Clock in on weekday arrivals and clock out when leaving',
    badge: 'session_page · GPS',
    icon: LucideIcons.mapPinCheck,
    source: '''target == session_page {
  if (location.inside() && weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])) {
    session.clock_in("Work");
    log("Clocked in at workplace");
  } else if (location.outside()) {
    session.clock_out();
  } else {
    session.continue();
  }
}''',
  ),
  _RuleTemplate(
    title: 'Weekday morning reminder',
    subtitle: 'Scheduled 08:00 system notification Monday through Friday',
    badge: 'notifications · schedule',
    icon: LucideIcons.bellRing,
    source: '''target == notifications {
  schedule("workday_morning") {
    at("08:00");
    repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);
    repeat.forever();
    notification.show("Morning check-in", "Ready to start your session");
  }
}''',
  ),
  _RuleTemplate(
    title: 'Arrival window reminder',
    subtitle:
        'Notify when arriving at your saved place between 08:00 and 09:00',
    badge: 'notifications · GPS',
    icon: LucideIcons.clock,
    source: '''target == notifications {
  if (time.between("08:00", "09:00") && location.inside() && weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])) {
    notification.show("At workplace", "Remember to clock in before 09:00");
  }
}''',
  ),
  _RuleTemplate(
    title: 'Monthly spending alert',
    subtitle: 'Show a notice when monthly expenses cross your threshold',
    badge: 'budget_page',
    icon: LucideIcons.wallet,
    source: '''target == budget_page {
  if (budget.expenses >= 5000 && budget.currency == "PHP") {
    app.toast("Monthly spending reached PHP 5,000");
  }
}''',
  ),
  _RuleTemplate(
    title: 'Low total balance notice',
    subtitle: 'Alert when all-time display-currency balance drops low',
    badge: 'app',
    icon: LucideIcons.trendingDown,
    source: '''target == app {
  if (budget.balance < 500) {
    app.toast("Balance is below 500");
  }
}''',
  ),
  _RuleTemplate(
    title: 'Low battery dark theme',
    subtitle: 'Switch to dark theme automatically below 20% unplugged',
    badge: 'settings_page',
    icon: LucideIcons.batteryLow,
    source: '''target == settings_page {
  if (device.battery <= 20 && device.charging == false) {
    settings.set_theme("dark");
  }
}''',
  ),
];

class RuleCodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool running, busy;
  final VoidCallback run, stop;
  final VoidCallback? create;
  final Iterable<String> settingFields;
  const RuleCodeEditor({
    super.key,
    required this.controller,
    required this.running,
    required this.busy,
    required this.run,
    required this.stop,
    this.create,
    this.settingFields = const [],
  });
  @override
  State<RuleCodeEditor> createState() => _RuleCodeEditorState();
}

class _RuleCodeEditorState extends State<RuleCodeEditor> {
  final focus = FocusNode();

  static const _knownStringValues = <String, List<String>>{
    'session.kind': ['OJT', 'Work', 'Study', 'Personal'],
    'settings.theme': ['light', 'dark', 'system'],
    'calendar.view': ['year', 'month', 'week', 'day'],
    'map.period': ['day', 'week', 'month', 'year', 'custom'],
    'device.orientation': ['portrait', 'landscape'],
    'device.ringer_mode': ['normal', 'vibrate', 'silent'],
    'budget.last.kind': ['expense', 'income', 'savings'],
    'budget.currency': ['PHP', 'USD', 'EUR', 'GBP', 'JPY', 'KRW', 'KWD'],
    'app.page': [
      'session_page',
      'map_page',
      'sessions_page',
      'budget_page',
      'settings_page',
      'calendar_page',
    ],
  };

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    focus.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(RuleCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    focus.removeListener(_onChanged);
    focus.dispose();
    super.dispose();
  }

  bool get _editable => !widget.running && !widget.busy;

  void insert(String text, {int? cursorOffset}) {
    if (!_editable) return;
    final value = widget.controller.value;
    final start = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final caret = start + (cursorOffset ?? text.length);
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: caret.clamp(0, nextText.length),
      ),
    );
    focus.requestFocus();
  }

  void insertPair(String open, String close) {
    if (!_editable) return;
    final value = widget.controller.value;
    final start = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    if (start != end) {
      final selected = value.text.substring(start, end);
      final wrapped = '$open$selected$close';
      widget.controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, wrapped),
        selection: TextSelection(
          baseOffset: start + open.length,
          extentOffset: start + open.length + selected.length,
        ),
      );
    } else {
      insert('$open$close', cursorOffset: open.length);
      return;
    }
    focus.requestFocus();
  }

  void _jumpToDiagnostic(String message) {
    final match = RegExp(r'Line (\d+), column (\d+)').firstMatch(message);
    if (match == null) return;
    final targetLine = int.tryParse(match.group(1)!) ?? 1;
    final targetCol = int.tryParse(match.group(2)!) ?? 1;
    final text = widget.controller.text;
    var line = 1;
    var offset = 0;
    while (offset < text.length && line < targetLine) {
      if (text.codeUnitAt(offset) == 10) line++;
      offset++;
    }
    var lineEnd = text.indexOf('\n', offset);
    if (lineEnd < 0) lineEnd = text.length;
    final caret = (offset + targetCol - 1).clamp(offset, lineEnd);
    widget.controller.selection = TextSelection.collapsed(offset: caret);
    focus.requestFocus();
  }

  ({int line, int col}) _cursorLineCol() {
    final value = widget.controller.value;
    if (!value.selection.isValid) return (line: 1, col: 1);
    final offset = value.selection.extentOffset.clamp(0, value.text.length);
    final prefix = value.text.substring(0, offset);
    final line = '\n'.allMatches(prefix).length + 1;
    final col = prefix.length - prefix.lastIndexOf('\n');
    return (line: line, col: col);
  }

  static String _typeBadge(String field) =>
      switch (RuleCatalog.fieldType(field)) {
        'bool' => 'BOOL',
        'number' => 'NUM',
        _ => 'TEXT',
      };

  static String _defaultComparisonSuffix(String field) {
    if (field == 'session.active') return '';
    return switch (RuleCatalog.fieldType(field)) {
      'bool' => ' == true',
      'number' => ' >= ',
      _ => ' == ""',
    };
  }

  Iterable<_CodeHint> options(TextEditingValue value) {
    if (widget.running || !value.selection.isValid) return const [];
    final cursorOffset = value.selection.start;
    final before = value.text.substring(0, cursorOffset);
    final after = value.text.substring(cursorOffset);

    // Lexical scan of `before` to distinguish comments, strings, braces, and parens.
    final lexPattern = RegExp(
      r'\s+|//[^\n]*|"(?:\\.|[^"\\\r\n])*"|==|!=|>=|<=|&&|\|\||[{}\[\](),;!=<>]|-?\d+(?:\.\d+)?|[A-Za-z_][A-Za-z_0-9.]*',
    );
    final blocks = <_EditorBlock>[];
    final parens = <_EditorParen>[];
    final tokens = <String>[];
    var scan = 0;
    var insideComment = false;
    int? unclosedQuoteOffset;

    while (scan < before.length) {
      final ch = before[scan];
      if (ch == '/' && scan + 1 < before.length && before[scan + 1] == '/') {
        final nl = before.indexOf('\n', scan + 2);
        if (nl < 0) {
          insideComment = true;
          break;
        }
        scan = nl + 1;
        continue;
      }
      if (ch == '"') {
        final strMatch = RegExp(r'"(?:\\.|[^"\\\r\n])*"')
            .matchAsPrefix(before, scan);
        if (strMatch == null) {
          unclosedQuoteOffset = scan;
          break;
        }
        tokens.add(strMatch.group(0)!);
        scan = strMatch.end;
        continue;
      }
      final m = lexPattern.matchAsPrefix(before, scan);
      if (m == null) {
        scan++;
        continue;
      }
      final tok = m.group(0)!;
      scan = m.end;
      if (tok.trim().isEmpty) continue;

      if (tok == '{') {
        final prev1 = tokens.isNotEmpty ? tokens.last : '';
        final prev3 = tokens.length >= 3 ? tokens[tokens.length - 3] : '';
        final prev2 = tokens.length >= 2 ? tokens[tokens.length - 2] : '';
        if (prev3 == 'target' && prev2 == '==') {
          blocks.add(
            _EditorBlock(
              _EditorBlockKind.target,
              target: prev1,
              startOffset: scan,
            ),
          );
        } else if (prev1 == ')' &&
            tokens.length >= 4 &&
            tokens[tokens.length - 4] == 'schedule') {
          blocks.add(
            _EditorBlock(_EditorBlockKind.schedule, startOffset: scan),
          );
        } else if (prev1 == ')' || prev1 == 'else') {
          blocks.add(_EditorBlock(_EditorBlockKind.branch, startOffset: scan));
        } else {
          blocks.add(_EditorBlock(_EditorBlockKind.other, startOffset: scan));
        }
      } else if (tok == '}') {
        final popped = blocks.isNotEmpty ? blocks.removeLast() : null;
        if (blocks.isNotEmpty && popped != null) {
          blocks.last.lastClosedChild = popped.kind;
        }
      } else if (tok == '(') {
        final prev = tokens.isNotEmpty ? tokens.last : '';
        if (prev == 'if') {
          parens.add(const _EditorParen(_EditorParenKind.condition));
        } else if (RegExp(r'^[A-Za-z_][A-Za-z_0-9.]*$').hasMatch(prev)) {
          parens.add(_EditorParen(_EditorParenKind.call, callee: prev));
        } else {
          parens.add(const _EditorParen(_EditorParenKind.group));
        }
      } else if (tok == ')') {
        if (parens.isNotEmpty) parens.removeLast();
      } else if (blocks.isNotEmpty &&
          blocks.last.lastClosedChild != null &&
          tok != 'else' &&
          !(tok.startsWith('el') && scan == before.length) &&
          !(tok.startsWith('if') &&
              tokens.isNotEmpty &&
              tokens.last == 'else' &&
              scan == before.length) &&
          !(tok.startsWith('sc') && scan == before.length)) {
        blocks.last.lastClosedChild = null;
      }
      tokens.add(tok);
    }

    if (insideComment) return const [];

    // Handle completion inside an unclosed string literal (e.g., data.get("... or enum string).
    if (unclosedQuoteOffset != null) {
      final quoteOffset = unclosedQuoteOffset;
      final typedInQuote = before.substring(quoteOffset + 1);
      final beforeQuote = before.substring(0, quoteOffset).trimRight();
      if (RegExp(r'data\.get\s*\($').hasMatch(beforeQuote)) {
        final consumeAfter = after.startsWith('")')
            ? 2
            : after.startsWith('"')
            ? 1
            : 0;
        final allFields = <String, (String, String)>{
          for (final e in RuleCatalog.fields.entries)
            e.key: (e.value, _typeBadge(e.key)),
          for (final s in widget.settingFields.where(
            (f) => !RuleCatalog.fields.containsKey(f),
          ))
            s: ('Saved setting · available automatically', 'TEXT'),
        };
        return allFields.entries
            .where((e) => e.key.startsWith(typedInQuote))
            .take(12)
            .map((e) {
              final suffix = consumeAfter == 2 ? '' : '") == ';
              final insertText = '${e.key}$suffix';
              final nextSource = value.text.replaceRange(
                quoteOffset + 1,
                cursorOffset + consumeAfter,
                insertText,
              );
              return _CodeHint(
                e.key,
                e.value.$1,
                nextSource,
                quoteOffset + 1 + insertText.length,
                badge: e.value.$2,
              );
            });
      }
      final cmpMatch = RegExp(
        r'(?:data\.get\(\s*"([A-Za-z_0-9.]+)"\s*\)|([A-Za-z_][A-Za-z_0-9.]*))\s*(?:==|!=)\s*$',
      ).firstMatch(beforeQuote);
      final cmpField = cmpMatch?.group(1) ?? cmpMatch?.group(2);
      final enumVals = cmpField != null ? _knownStringValues[cmpField] : null;
      if (enumVals != null) {
        final consumeQuote = after.startsWith('"') ? 1 : 0;
        return enumVals
            .where(
              (v) => v.toLowerCase().startsWith(typedInQuote.toLowerCase()),
            )
            .map((v) {
              final insertText = '$v"';
              final nextSource = value.text.replaceRange(
                quoteOffset + 1,
                cursorOffset + consumeQuote,
                insertText,
              );
              return _CodeHint(
                '"$v"',
                'Allowed value for $cmpField',
                nextSource,
                quoteOffset + 1 + insertText.length,
                badge: 'VALUE',
              );
            });
      }
      return const [];
    }

    final prefix = RegExp(r'[A-Za-z_.]*$').firstMatch(before)!;
    final query = prefix.group(0)!;
    final choices = <String, (String, String, String)>{};

    // 1. Completing target name right after `target == `
    if (blocks.isEmpty &&
        RegExp(r'target\s*==\s*[A-Za-z_]*$').hasMatch(before)) {
      for (final target in RuleCatalog.targets) {
        choices[target] = (
          target == 'notifications'
              ? '$target {\n  schedule("daily_reminder") {\n    at("08:00");\n    repeat.daily();\n    repeat.forever();\n    notification.show("Reminder", "Message");\n  }\n}'
              : '$target {\n  if (true) {\n    log("Message");\n  }\n}',
          'Target $target',
          'TARGET',
        );
      }
    } else {
      final currentTarget = blocks
          .where((b) => b.kind == _EditorBlockKind.target)
          .lastOrNull
          ?.target;
      final inCondition = parens.any(
        (p) => p.kind == _EditorParenKind.condition,
      );
      final topBlock = blocks.lastOrNull;
      final topParen = parens.lastOrNull;

      if (blocks.isEmpty && !inCondition) {
        // Top level outside any target block.
        choices['target'] = (
          'target == ',
          'Choose a page or data target',
          'BLOCK',
        );
      } else if (!inCondition &&
          topBlock != null &&
          topBlock.kind == _EditorBlockKind.target) {
        // Directly inside `target == <name> { ... }`
        final beforeQuery = before.substring(0, prefix.start).trimRight();
        if (beforeQuery.endsWith('else')) {
          choices['if'] = ('if (', 'Add another condition branch', 'FLOW');
        } else if (topBlock.lastClosedChild == _EditorBlockKind.branch) {
          choices['else if'] = ('else if (', 'Another condition', 'FLOW');
          choices['else'] = (
            'else {\n  ${currentTarget == 'session_page' ? 'session.continue();' : 'log("Message");'}\n}',
            'Fallback branch',
            'FLOW',
          );
          if (currentTarget == 'notifications') {
            choices['schedule'] = (
              'schedule("daily_reminder") {\n  at("08:00");\n  repeat.daily();\n  repeat.forever();\n  notification.show("Reminder", "Message");\n}',
              'Create a scheduled notification',
              'SCHEDULE',
            );
          }
        } else {
          choices['if'] = ('if (', 'Start a condition', 'FLOW');
          if (currentTarget == 'notifications') {
            choices['schedule'] = (
              'schedule("daily_reminder") {\n  at("08:00");\n  repeat.daily();\n  repeat.forever();\n  notification.show("Reminder", "Message");\n}',
              'Create a scheduled notification',
              'SCHEDULE',
            );
          }
        }
      } else if (!inCondition &&
          topBlock != null &&
          topBlock.kind == _EditorBlockKind.schedule) {
        // Inside `schedule("...") { ... }`
        if (topParen?.kind == _EditorParenKind.call &&
            topParen?.callee == 'repeat.weekdays') {
          for (final day in const [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun',
          ]) {
            choices[day] = ('"$day"', 'Weekday $day', 'DAY');
          }
        } else {
          final scheduleSlice = before.substring(
            topBlock.startOffset.clamp(0, before.length),
            prefix.start,
          );
          final hasAt = RegExp(r'\bat\s*\(').hasMatch(scheduleSlice);
          final hasCadence = RegExp(r'\brepeat\.(?:daily|weekdays)\s*\(')
              .hasMatch(scheduleSlice);
          final hasLimit = RegExp(r'\brepeat\.(?:forever|count)\s*\(')
              .hasMatch(scheduleSlice);
          final hasShow = RegExp(r'\bnotification\.show\s*\(')
              .hasMatch(scheduleSlice);

          if (!hasAt) {
            choices['at'] = (
              'at("08:00");',
              'Local 24-hour delivery time',
              'SCHEDULE',
            );
          }
          if (!hasCadence) {
            choices['repeat.daily'] = (
              'repeat.daily();',
              'Repeat each local day',
              'SCHEDULE',
            );
            choices['repeat.weekdays'] = (
              'repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);',
              'Repeat only on selected local weekdays',
              'SCHEDULE',
            );
          }
          if (!hasLimit) {
            choices['repeat.forever'] = (
              'repeat.forever();',
              'Repeat until stopped',
              'SCHEDULE',
            );
            choices['repeat.count'] = (
              'repeat.count(10);',
              'Total successful deliveries, including the first',
              'SCHEDULE',
            );
          }
          if (!hasShow) {
            choices['notification.show'] = (
              'notification.show("Reminder", "Message");',
              'System notification title and body',
              'ACTION',
            );
          }
        }
      } else if (inCondition) {
        // Inside `if (...)` or `else if (...)`
        final beforeQuery = before.substring(0, prefix.start).trimRight();
        final cmpMatch = RegExp(
          r'(?:data\.get\(\s*"([A-Za-z_0-9.]+)"\s*\)|([A-Za-z_][A-Za-z_0-9.]*))\s*(==|!=|>=|<=|>|<)\s*$',
        ).firstMatch(beforeQuery);
        final cmpField = cmpMatch?.group(1) ?? cmpMatch?.group(2);
        if (topParen?.kind == _EditorParenKind.call &&
            topParen?.callee == 'weekday.in') {
          for (final day in const [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun',
          ]) {
            choices[day] = ('"$day"', 'Weekday $day', 'DAY');
          }
        } else if (cmpField != null) {
          if (RuleCatalog.booleanFields.contains(cmpField)) {
            choices['true'] = ('true', '$cmpField is true', 'BOOL');
            choices['false'] = ('false', '$cmpField is false', 'BOOL');
          } else if (_knownStringValues.containsKey(cmpField)) {
            for (final v in _knownStringValues[cmpField]!) {
              choices[v] = ('"$v"', 'Allowed value for $cmpField', 'VALUE');
            }
          }
        } else {
          choices.addAll({
            'location.inside': (
              'location.inside()',
              'Inside the configured place radius',
              'GPS',
            ),
            'location.outside': (
              'location.outside()',
              'Outside the configured place radius',
              'GPS',
            ),
            'time.between': (
              'time.between("08:00", "17:00")',
              'Local 24-hour time, overnight supported',
              'TIME',
            ),
            'weekday.in': (
              'weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])',
              'Select weekdays',
              'TIME',
            ),
            'data.get': (
              'data.get("settings.key") == "value"',
              'Read any saved setting by key',
              'DATA',
            ),
            'true': ('true', 'Always matches', 'BOOL'),
            'false': ('false', 'Never matches', 'BOOL'),
          });
          for (final field in RuleCatalog.fields.entries) {
            choices[field.key] = (
              field.key == 'session.active' ? field.key : '${field.key} == ',
              field.value,
              _typeBadge(field.key),
            );
          }
          for (final field in widget.settingFields.where(
            (f) => !RuleCatalog.fields.containsKey(f),
          )) {
            choices[field] = (
              'data.get(${jsonEncode(field)}) == ',
              'Saved setting · available automatically',
              'TEXT',
            );
          }
        }
      } else if (topBlock != null && topBlock.kind == _EditorBlockKind.branch) {
        // Inside an action block `{ ... }`
        if (topParen?.kind == _EditorParenKind.call) {
          final callee = topParen?.callee;
          if (callee == 'session.clock_in') {
            for (final k in _knownStringValues['session.kind']!) {
              choices[k] = ('"$k"', 'Clock into $k session', 'VALUE');
            }
          } else if (callee == 'settings.set_theme') {
            for (final t in _knownStringValues['settings.theme']!) {
              choices[t] = ('"$t"', 'Switch to $t theme', 'VALUE');
            }
          } else if (callee == 'settings.set_sound') {
            choices['true'] = ('true', 'Enable sound effects', 'BOOL');
            choices['false'] = ('false', 'Disable sound effects', 'BOOL');
          }
        } else {
          if (currentTarget == 'session_page') {
            choices['session.clock_in'] = (
              'session.clock_in("Work");',
              'Start a session (OJT, Work, Study, Personal)',
              'ACTION',
            );
            choices['session.clock_out'] = (
              'session.clock_out();',
              'End the session owned by this rule',
              'ACTION',
            );
            choices['session.continue'] = (
              'session.continue();',
              'Keep the session running',
              'ACTION',
            );
          }
          if (currentTarget == 'budget_page') {
            choices['budget.add_expense'] = (
              'budget.add_expense(100, "PHP", "Food", "Lunch");',
              'Record an expense in Finance',
              'ACTION',
            );
          }
          if (currentTarget == 'settings_page') {
            choices['settings.set_theme'] = (
              'settings.set_theme("dark");',
              'light, dark or system',
              'ACTION',
            );
            choices['settings.set_sound'] = (
              'settings.set_sound(true);',
              'Enable or disable sound effects',
              'ACTION',
            );
          }
          if (currentTarget == 'notifications') {
            choices['notification.show'] = (
              'notification.show("Reminder", "Message");',
              'Send a system notification when this condition matches',
              'ACTION',
            );
          }
          choices['app.toast'] = (
            'app.toast("Message");',
            'Show a top toast when app reconciles',
            'ACTION',
          );
          choices['log'] = (
            'log("Message");',
            'Append an activity, when logging is enabled',
            'ACTION',
          );
        }
      }
    }

    final lowerQuery = query.toLowerCase();
    return choices.entries
        .where((e) => e.key.toLowerCase().startsWith(lowerQuery))
        .take(12)
        .map((entry) {
          final insertText = entry.value.$1;
          final source = value.text.replaceRange(
            prefix.start,
            cursorOffset,
            insertText,
          );
          final slot = insertText.indexOf('Message');
          final cursor = prefix.start + (slot >= 0 ? slot : insertText.length);
          return _CodeHint(
            entry.key,
            entry.value.$2,
            source,
            cursor,
            badge: entry.value.$3,
          );
        });
  }

  Future<void> _openTemplates(BuildContext context) async {
    if (!_editable) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final chosen = await panel<_RuleTemplate>(
      context,
      PanelContent(
        header: PanelHeading(
          title: 'Starter templates',
          trailing: IconButton(
            tooltip: 'Close templates',
            onPressed: withFeedback(() => Navigator.pop(context)),
            icon: const Icon(LucideIcons.x, size: 18),
          ),
        ),
        scrollable: true,
        child: ListView.separated(
          itemCount: _ruleTemplates.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            final t = _ruleTemplates[i];
            final colors = Theme.of(c).colorScheme;
            return Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: withFeedback(() => Navigator.pop(c, t)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          t.icon,
                          size: 18,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    t.badge,
                                    style: TextStyle(
                                      fontFamily: 'Geist Mono',
                                      fontSize: 10,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    widget.controller.value = TextEditingValue(
      text: chosen.source,
      selection: TextSelection.collapsed(offset: chosen.source.length),
    );
    focus.requestFocus();
  }

  Future<void> _openReference(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final inserted = await panel<(String, int?)>(
      context,
      _SyntaxReferenceSheet(
        settingFields: widget.settingFields.toList(),
        canInsert: _editable,
      ),
    );
    if (inserted == null || !mounted || !_editable) return;
    insert(inserted.$1, cursorOffset: inserted.$2);
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final source = widget.controller.text;
    final trimmed = source.trim();
    Map<String, dynamic>? compiled;
    String? compileError;
    if (trimmed.isNotEmpty) {
      try {
        compiled = RuleCompiler.compile(source);
      } on FormatException catch (e) {
        compileError = e.message;
      }
    }
    final cursorPos = _cursorLineCol();
    final okColor = dark ? const Color(0xFF55C486) : const Color(0xFF1E8E5A);

    String validSummary = 'Valid syntax';
    if (compiled != null) {
      final targetCount = (compiled['targets'] as List? ?? const []).length;
      final scheduleCount = (compiled['schedules'] as List? ?? const []).length;
      final parts = <String>['Syntax valid'];
      if (targetCount > 0) {
        parts.add('$targetCount ${targetCount == 1 ? 'target' : 'targets'}');
      }
      if (scheduleCount > 0) {
        parts.add(
          '$scheduleCount ${scheduleCount == 1 ? 'schedule' : 'schedules'}',
        );
      }
      if (compiled['needsLocation'] == true) {
        parts.add('GPS');
      }
      validSummary = parts.join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rule editor',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.create != null)
              IconButton(
                tooltip: 'New rule',
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: withFeedback(widget.create),
              ),
            IconButton(
              tooltip: 'Allow precise reminders',
              icon: const Icon(LucideIcons.clock, size: 18),
              onPressed: widget.busy
                  ? null
                  : withFeedback(() {
                      guarded(c, () async {
                        final allowed = await PermissionHints.request<bool>(
                          c,
                          'exactReminderPermission',
                        );
                        if (allowed == null) return;
                        if (c.mounted) {
                          toast(
                            c,
                            allowed ? 'Precise reminders enabled' : 'Allow alarms & reminders, then return to FrekiHub',
                          );
                        }
                      });
                    }),
            ),
            IconButton(
              tooltip: 'Validate syntax',
              icon: const Icon(LucideIcons.check, size: 18),
              onPressed: withFeedback(() {
                try {
                  RuleCompiler.compile(widget.controller.text);
                  toast(c, 'Syntax valid');
                } on FormatException catch (e) {
                  _jumpToDiagnostic(e.message);
                  toast(c, e.message, error: true);
                }
              }),
            ),
            IconButton(
              tooltip: widget.running ? 'Stop rule' : 'Run rule',
              onPressed: widget.busy
                  ? null
                  : withFeedback(
                      widget.running
                          ? widget.stop
                          : () {
                              try {
                                RuleCompiler.compile(widget.controller.text);
                                widget.run();
                              } on FormatException catch (e) {
                                _jumpToDiagnostic(e.message);
                                toast(c, e.message, error: true);
                              }
                            },
                    ),
              icon: SkeletonValue(
                loading: widget.busy,
                child: Icon(
                  widget.running ? LucideIcons.square : LucideIcons.play,
                  size: 18,
                ),
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.running
                    ? colors.errorContainer
                    : colors.primaryContainer,
                foregroundColor: widget.running
                    ? colors.onErrorContainer
                    : colors.onPrimaryContainer,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EditorUtilityChip(
                icon: LucideIcons.sparkles,
                label: 'Templates',
                onTap: _editable ? () => _openTemplates(c) : null,
              ),
              _EditorUtilityChip(
                icon: LucideIcons.bookOpen,
                label: 'Fields & actions',
                onTap: () => _openReference(c),
              ),
              if (widget.running)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: okColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.lock, size: 12, color: okColor),
                      const SizedBox(width: 5),
                      Text(
                        'Running · Stop to edit',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: okColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        RawAutocomplete<_CodeHint>(
          optionsViewOpenDirection: KeyboardOverlay.imeBottomOf(c) > 0
              ? OptionsViewOpenDirection.up
              : OptionsViewOpenDirection.down,
          textEditingController: widget.controller,
          focusNode: focus,
          displayStringForOption: (hint) => hint.source,
          optionsBuilder: options,
          onSelected: (hint) => widget.controller.selection =
              TextSelection.collapsed(offset: hint.cursor),
          fieldViewBuilder: (c, controller, node, submit) => TextField(
            controller: controller,
            focusNode: node,
            readOnly: widget.running,
            minLines: 7,
            maxLines: 14,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              fontFamily: 'Geist Mono',
              fontSize: 12.5,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: 'target == session_page {\n  if (location.inside()) {\n    session.clock_in("Work");\n  }\n}',
              fillColor: colors.surfaceContainerLow,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: compileError != null
                      ? colors.error.withValues(alpha: .45)
                      : colors.outlineVariant.withValues(alpha: .55),
                ),
              ),
            ),
          ),
          optionsViewBuilder: (c, select, hints) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              color: colors.surfaceContainerHigh,
              child: SizedBox(
                width: math.min(360, MediaQuery.sizeOf(c).width - 56),
                height: math.min(236, hints.length * 60.0),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final hint in hints)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                hint.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (hint.badge.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  hint.badge,
                                  style: TextStyle(
                                    fontFamily: 'Geist Mono',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          hint.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: withFeedback(() => select(hint)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Live syntax readiness & cursor telemetry bar (errors surface in the shared top toast pill)
        if (compileError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Material(
                  color: colors.error.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(99),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: withFeedback(() {
                      _jumpToDiagnostic(compileError!);
                      toast(c, compileError, error: true);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.circleAlert,
                            size: 13,
                            color: colors.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Syntax incomplete · tap to inspect',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Ln ${cursorPos.line}, Col ${cursorPos.col} · ${source.length}/8192',
                  style: TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  compiled != null ? LucideIcons.circleCheck : LucideIcons.code,
                  size: 14,
                  color: compiled != null ? okColor : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    compiled != null
                        ? validSummary
                        : 'Choose a template or start with target ==',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: compiled != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: compiled != null
                          ? okColor
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ln ${cursorPos.line}, Col ${cursorPos.col} · ${source.length}/8192',
                  style: TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final snippet in <(String, VoidCallback)>[
                (
                  'Target',
                  () => insert(
                    source.trim().isEmpty ? 'target == ' : '\ntarget == ',
                  ),
                ),
                (
                  'Condition',
                  () => insert('\n  if () {\n    \n  }', cursorOffset: 7),
                ),
                (
                  'Else if',
                  () => insert(' else if () {\n    \n  }', cursorOffset: 10),
                ),
                (
                  'Schedule',
                  () => insert(
                    '\n  schedule("reminder") {\n    at("08:00");\n    repeat.daily();\n    repeat.forever();\n    notification.show("Reminder", "Message");\n  }',
                    cursorOffset: 13,
                  ),
                ),
                ('Action', () => insert('\n    ')),
                ('{ }', () => insertPair('{', '}')),
                ('( )', () => insertPair('(', ')')),
                ('" "', () => insertPair('"', '"')),
                ('==', () => insert(' == ')),
                ('&&', () => insert(' && ')),
                ('||', () => insert(' || ')),
                (';', () => insert(';')),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _EditorSnippetPill(
                    label: snippet.$1,
                    mono: snippet.$1.length <= 3,
                    onTap: _editable ? snippet.$2 : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Rules execute once when the matched branch changes. Stop pauses the rule; it does not clock out an active session.',
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EditorUtilityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _EditorUtilityChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? withFeedback(onTap) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: enabled
                    ? colors.onSurface
                    : colors.onSurfaceVariant.withValues(alpha: .45),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: enabled
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(alpha: .45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorSnippetPill extends StatelessWidget {
  final String label;
  final bool mono;
  final VoidCallback? onTap;
  const _EditorSnippetPill({
    required this.label,
    this.mono = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? withFeedback(onTap) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: mono ? 'Geist Mono' : 'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: enabled
                  ? colors.onSurface
                  : colors.onSurfaceVariant.withValues(alpha: .4),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyntaxReferenceItem {
  final String category, label, detail, badge, snippet;
  final int? cursorOffset;
  const _SyntaxReferenceItem({
    required this.category,
    required this.label,
    required this.detail,
    required this.badge,
    required this.snippet,
    this.cursorOffset,
  });
}

class _SyntaxReferenceSheet extends StatefulWidget {
  final List<String> settingFields;
  final bool canInsert;
  const _SyntaxReferenceSheet({
    required this.settingFields,
    required this.canInsert,
  });

  @override
  State<_SyntaxReferenceSheet> createState() => _SyntaxReferenceSheetState();
}

class _SyntaxReferenceSheetState extends State<_SyntaxReferenceSheet> {
  String query = '';
  String category = 'All';

  late final List<_SyntaxReferenceItem> _items = _buildItems();

  List<_SyntaxReferenceItem> _buildItems() {
    final items = <_SyntaxReferenceItem>[
      for (final t in RuleCatalog.targets)
        _SyntaxReferenceItem(
          category: 'Targets',
          label: 'target == $t',
          detail: switch (t) {
            'session_page' => 'Allows session.clock_in, clock_out, continue',
            'budget_page' => 'Allows budget.add_expense',
            'settings_page' => 'Allows settings.set_theme, set_sound',
            'notifications' => 'Allows schedule(...) and notification.show',
            _ => 'Allows log(...) and app.toast(...) when matched',
          },
          badge: 'TARGET',
          snippet: 'target == $t {\n  if () {\n    \n  }\n}',
          cursorOffset: ('target == $t {\n  if (').length,
        ),
      const _SyntaxReferenceItem(
        category: 'Conditions',
        label: 'location.inside()',
        detail: 'Fresh accurate fix inside this rule’s configured place radius',
        badge: 'GPS',
        snippet: 'location.inside()',
      ),
      const _SyntaxReferenceItem(
        category: 'Conditions',
        label: 'location.outside()',
        detail:
            'Fresh accurate fix outside this rule’s configured place radius',
        badge: 'GPS',
        snippet: 'location.outside()',
      ),
      const _SyntaxReferenceItem(
        category: 'Conditions',
        label: 'time.between("08:00", "17:00")',
        detail: 'Local 24-hour range (start inclusive, end exclusive; overnight supported)',
        badge: 'TIME',
        snippet: 'time.between("08:00", "17:00")',
      ),
      const _SyntaxReferenceItem(
        category: 'Conditions',
        label: 'weekday.in(["Mon", "Fri"])',
        detail: 'Match local weekdays (Mon, Tue, Wed, Thu, Fri, Sat, Sun)',
        badge: 'TIME',
        snippet: 'weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])',
      ),
      const _SyntaxReferenceItem(
        category: 'Schedules',
        label: 'schedule("name") { … }',
        detail: 'Fixed-time reminder inside target == notifications',
        badge: 'SCHEDULE',
        snippet: 'schedule("daily_reminder") {\n  at("08:00");\n  repeat.daily();\n  repeat.forever();\n  notification.show("Reminder", "Message");\n}',
      ),
      const _SyntaxReferenceItem(
        category: 'Schedules',
        label: 'repeat.weekdays([…])',
        detail: 'Deliver scheduled reminders on chosen weekdays',
        badge: 'SCHEDULE',
        snippet: 'repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);',
      ),
      const _SyntaxReferenceItem(
        category: 'Schedules',
        label: 'repeat.count(10)',
        detail: 'Stop after N successful reminder deliveries (1–10,000)',
        badge: 'SCHEDULE',
        snippet: 'repeat.count(10);',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'session.clock_in("Work");',
        detail: 'target == session_page · OJT, Work, Study, Personal',
        badge: 'session_page',
        snippet: 'session.clock_in("Work");',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'session.clock_out();',
        detail: 'target == session_page · ends only the session started by this rule',
        badge: 'session_page',
        snippet: 'session.clock_out();',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'session.continue();',
        detail: 'target == session_page · keeps running session active',
        badge: 'session_page',
        snippet: 'session.continue();',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'budget.add_expense(100, "PHP", "Food", "Lunch");',
        detail: 'target == budget_page · queues an expense in major units',
        badge: 'budget_page',
        snippet: 'budget.add_expense(100, "PHP", "Food", "Lunch");',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'notification.show("Title", "Body");',
        detail: 'target == notifications · posts a local reminder notification',
        badge: 'notifications',
        snippet: 'notification.show("Reminder", "Message");',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'settings.set_theme("dark");',
        detail: 'target == settings_page · light, dark, system',
        badge: 'settings_page',
        snippet: 'settings.set_theme("dark");',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'settings.set_sound(true);',
        detail: 'target == settings_page · true or false',
        badge: 'settings_page',
        snippet: 'settings.set_sound(true);',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'app.toast("Message");',
        detail: 'Any target · displays top notice on reconciliation',
        badge: 'any target',
        snippet: 'app.toast("Message");',
      ),
      const _SyntaxReferenceItem(
        category: 'Actions',
        label: 'log("Message");',
        detail: 'Any target · appends activity log when logging is enabled',
        badge: 'any target',
        snippet: 'log("Message");',
      ),
      for (final field in RuleCatalog.fields.entries)
        _SyntaxReferenceItem(
          category: 'Fields',
          label: field.key,
          detail: field.value,
          badge: _RuleCodeEditorState._typeBadge(field.key),
          snippet:
              '${field.key}${_RuleCodeEditorState._defaultComparisonSuffix(field.key)}',
          cursorOffset: RuleCatalog.fieldType(field.key) == 'string'
              ? '${field.key} == "'.length
              : null,
        ),
      for (final pref in widget.settingFields.where(
        (f) => !RuleCatalog.fields.containsKey(f),
      ))
        _SyntaxReferenceItem(
          category: 'Fields',
          label: pref,
          detail: 'Saved preference · read with data.get("$pref")',
          badge: 'TEXT',
          snippet: 'data.get(${jsonEncode(pref)}) == ""',
          cursorOffset: 'data.get(${jsonEncode(pref)}) == "'.length,
        ),
    ];
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final q = query.trim().toLowerCase();
    final filtered = _items.where((item) {
      if (category != 'All' && item.category != category) return false;
      if (q.isEmpty) return true;
      return item.label.toLowerCase().contains(q) ||
          item.detail.toLowerCase().contains(q) ||
          item.badge.toLowerCase().contains(q);
    }).toList();

    return PanelContent(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PanelHeading(
            title: 'Syntax reference',
            trailing: IconButton(
              tooltip: 'Close reference',
              onPressed: withFeedback(() => Navigator.pop(context)),
              icon: const Icon(LucideIcons.x, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: 'Search fields, targets, actions…',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: withFeedback(() => setState(() => query = '')),
                      icon: const Icon(LucideIcons.x, size: 16),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in const [
                  'All',
                  'Fields',
                  'Actions',
                  'Conditions',
                  'Schedules',
                  'Targets',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: category == cat,
                      onSelected: (_) {
                        ActionFeedback.tap();
                        setState(() => category = cat);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      scrollable: true,
      child: filtered.isEmpty
          ? ListView(
              children: const [
                EmptyState(
                  'No matching syntax items',
                  'Try searching by domain like budget, session, map, or device.',
                  LucideIcons.searchX,
                ),
              ],
            )
          : ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (c, i) {
                final item = filtered[i];
                return Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.canInsert
                        ? withFeedback(
                            () => Navigator.pop(c, (
                              item.snippet,
                              item.cursorOffset,
                            )),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  style: const TextStyle(
                                    fontFamily: 'Geist Mono',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.detail,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.badge,
                              style: TextStyle(
                                fontFamily: 'Geist Mono',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
