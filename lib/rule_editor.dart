part of 'screens.dart';

class _CodeHint {
  final String label, detail, source;
  final int cursor;
  const _CodeHint(this.label, this.detail, this.source, this.cursor);
}

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
  String? error;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  void insert(String text) {
    final value = widget.controller.value;
    final position = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(position, position, text),
      selection: TextSelection.collapsed(offset: position + text.length),
    );
    focus.requestFocus();
  }

  Iterable<_CodeHint> options(TextEditingValue value) {
    if (widget.running) return const [];
    if (!value.selection.isValid) return const [];
    final before = value.text.substring(0, value.selection.start);
    final prefix = RegExp(r'[A-Za-z_.]*$').firstMatch(before)!;
    final query = prefix.group(0)!;
    final choices = <String, (String, String)>{};
    if (RegExp(r'target\s*==\s*[A-Za-z_]*$').hasMatch(before)) {
      for (final target in RuleCatalog.targets) {
        choices[target] = (
          target == 'notifications'
              ? '$target {\n  schedule("daily_reminder") {\n    at("08:00");\n    repeat.daily();\n    repeat.forever();\n    notification.show("Reminder", "Message");\n  }\n}'
              : '$target {\n  if (true) {\n    log("Message");\n  }\n}',
          'Target $target',
        );
      }
    } else {
      choices.addAll({
        'target': ('target == ', 'Choose a page or data target'),
        'if': ('if (', 'Start a condition'),
        'else': ('else {\n  session.continue();\n}', 'Fallback branch'),
        'else if': ('else if (', 'Another condition'),
        'location.inside': (
          'location.inside()',
          'Inside the configured place radius',
        ),
        'location.outside': (
          'location.outside()',
          'Outside the configured place radius',
        ),
        'time.between': (
          'time.between("08:00", "17:00")',
          'Local 24-hour time, overnight supported',
        ),
        'weekday.in': (
          'weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])',
          'Select weekdays',
        ),
        'data.get': (
          'data.get("settings.key") == "value"',
          'Read any saved setting by key',
        ),
        'session.clock_in': ('session.clock_in("Work");', 'Start a session'),
        'session.clock_out': (
          'session.clock_out();',
          'End the session owned by this rule',
        ),
        'session.continue': ('session.continue();', 'Keep the session running'),
        'budget.add_expense': (
          'budget.add_expense(100, "PHP", "Food", "Lunch");',
          'Record a budget expense',
        ),
        'settings.set_theme': (
          'settings.set_theme("dark");',
          'light, dark or system',
        ),
        'settings.set_sound': (
          'settings.set_sound(true);',
          'Enable or disable sound effects',
        ),
        'app.toast': (
          'app.toast("Message");',
          'Show a top toast when app reconciles',
        ),
        'notification.show': (
          'notification.show("Reminder", "Message");',
          'Send a system notification when this condition matches',
        ),
        'log': (
          'log("Message");',
          'Append an activity, when logging is enabled',
        ),
      });
      for (final field in RuleCatalog.fields.entries) {
        choices[field.key] = (
          field.key == 'session.active' ? field.key : '${field.key} == ',
          field.value,
        );
      }
      for (final field in widget.settingFields.where(
        (f) => !RuleCatalog.fields.containsKey(f),
      )) {
        choices[field] = (
          'data.get(${jsonEncode(field)}) == ',
          'Saved setting · available automatically',
        );
      }
      final target = RegExp(r'target\s*==\s*(\w+)')
          .allMatches(before)
          .lastOrNull
          ?.group(1);
      final inCondition = before.lastIndexOf('if (') > before.lastIndexOf('{');
      const actions = [
        'session.clock_in',
        'session.clock_out',
        'session.continue',
        'budget.add_expense',
        'settings.set_theme',
        'settings.set_sound',
        'app.toast',
        'notification.show',
        'log',
      ];
      final lastBrace = before.lastIndexOf('{');
      final branch =
          lastBrace >= 0 &&
          (before.substring(0, lastBrace).trimRight().endsWith(')') ||
              before.substring(0, lastBrace).trimRight().endsWith('else'));
      choices.removeWhere((key, _) {
        if (inCondition) {
          return actions.contains(key) ||
              ['target', 'if', 'else', 'else if'].contains(key);
        }
        if (branch && !actions.contains(key)) return true;
        return (key.startsWith('session.clock') || key == 'session.continue') &&
                target != 'session_page' ||
            key == 'budget.add_expense' && target != 'budget_page' ||
            key.startsWith('settings.set_') && target != 'settings_page' ||
            key == 'notification.show' && target != 'notifications';
      });
      if (target == 'notifications' && !inCondition) {
        final inSchedule =
            before.lastIndexOf('schedule(') > before.lastIndexOf('}');
        if (inSchedule) {
          choices.clear();
          choices.addAll({
            'at': ('at("08:00");', 'Local 24-hour delivery time'),
            'repeat.daily': ('repeat.daily();', 'Repeat each local day'),
            'repeat.weekdays': (
              'repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);',
              'Repeat only on selected local weekdays',
            ),
            'repeat.forever': ('repeat.forever();', 'Repeat until stopped'),
            'repeat.count': (
              'repeat.count(10);',
              'Total successful deliveries, including the first',
            ),
            'notification.show': (
              'notification.show("Reminder", "Message");',
              'System notification title and body',
            ),
          });
        } else {
          choices['schedule'] = (
            'schedule("daily_reminder") {\n  at("08:00");\n  repeat.daily();\n  repeat.forever();\n  notification.show("Reminder", "Message");\n}',
            'Create a scheduled notification',
          );
        }
      }
    }
    return choices.entries.where((e) => e.key.startsWith(query)).take(8).map((
      entry,
    ) {
      final insert = entry.value.$1;
      final source = value.text.replaceRange(
        prefix.start,
        value.selection.start,
        insert,
      );
      final slot = insert.indexOf('Message');
      final cursor = prefix.start + (slot >= 0 ? slot : insert.length);
      return _CodeHint(entry.key, entry.value.$2, source, cursor);
    });
  }

  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Rule editor',
              style: TextStyle(fontWeight: FontWeight.w600),
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
                      final allowed =
                          await NativeSession.channel.invokeMethod<bool>(
                            'exactReminderPermission',
                          ) ??
                          false;
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
                setState(() => error = null);
                toast(c, 'Syntax valid');
              } on FormatException catch (e) {
                setState(() => error = e.message);
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
                              setState(() => error = null);
                              widget.run();
                            } on FormatException catch (e) {
                              setState(() => error = e.message);
                              toast(c, 'Rule could not run · fix the syntax');
                            }
                          },
                  ),
            icon: Icon(
              widget.running ? LucideIcons.square : LucideIcons.play,
              size: 18,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.primaryContainer,
            ),
          ),
        ],
      ),
      RawAutocomplete<_CodeHint>(
        optionsViewOpenDirection: MediaQuery.viewInsetsOf(c).bottom > 0
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
          minLines: 6,
          maxLines: 12,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            fontFamily: 'Geist Mono',
            fontSize: 12,
            height: 1.6,
          ),
          decoration: InputDecoration(
            hintText: 'target == session_page { … }',
            errorText: error,
            errorMaxLines: 4,
          ),
          onChanged: (_) {
            if (error != null) setState(() => error = null);
          },
        ),
        optionsViewBuilder: (c, select, hints) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(c).colorScheme.surfaceContainerHigh,
            child: SizedBox(
              width: math.min(360, MediaQuery.sizeOf(c).width - 72),
              height: math.min(220, hints.length * 64.0),
              child: ListView(
                children: [
                  for (final hint in hints)
                    ListTile(
                      title: Text(
                        hint.label,
                        style: const TextStyle(
                          fontFamily: 'Geist Mono',
                          fontSize: 12,
                        ),
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
      Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: withFeedback(() => insert('\ntarget == ')),
            child: const Text('Target'),
          ),
          TextButton(
            onPressed: withFeedback(() => insert('\n  if (')),
            child: const Text('Condition'),
          ),
          TextButton(
            onPressed: withFeedback(() => insert('\n    ')),
            child: const Text('Action'),
          ),
        ],
      ),
      const Text(
        'Rules execute once when the matched branch changes. Stop pauses the rule; it does not clock out an active session.',
        style: TextStyle(fontSize: 11),
      ),
    ],
  );
}
