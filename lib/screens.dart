import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData,
        DatePickerDateOrder;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'automation_sync.dart';
import 'design.dart';
import 'services.dart';
import 'theme_reveal.dart';
import 'rule_language.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
part 'today.dart';
part 'calendar.dart';
part 'history.dart';
part 'budget.dart';
part 'settings.dart';
part 'forms.dart';
part 'pickers.dart';
part 'activity.dart';
part 'controls.dart';
part 'rule_editor.dart';

Future<void> guarded(
  BuildContext c,
  Future<void> Function() operation, {
  String? success,
}) async {
  try {
    await operation();
    if (c.mounted && success != null) {
      toast(c, success);
    }
  } catch (e) {
    if (c.mounted) {
      toast(
        c,
        e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : 'Could not save: $e',
      );
    }
  }
}

Widget selectField(
  String label,
  String value,
  List<String> values,
  ValueChanged<String> changed,
) => _SelectionField(
  label: label,
  value: value,
  values: values,
  changed: changed,
);
Widget spaced(Widget child) =>
    Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
String sessionDate(AppData d, Session s) {
  final date = calendarDate(s.day);
  final format = d.prefs['dateFormat'] ?? 'EEE, d MMM';
  if (format == 'relative') {
    final today = DateTime.now();
    final diff = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
    return diff == 0
        ? 'Today'
        : diff == 1
        ? 'Yesterday'
        : diff >= 0
        ? '$diff days ago'
        : 'In ${-diff} days';
  }
  return DateFormat(format).format(date);
}

String clockTime(AppData d, int ms) =>
    DateFormat(d.prefs['clockFormat'] == '12' ? 'h:mm a' : 'HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
int durationOf(Session s) => math.max(
  0,
  ((s.ended ?? DateTime.now().millisecondsSinceEpoch) - s.started) ~/ 1000,
);
Future<bool> deleteSession(BuildContext c, WidgetRef ref, Session s) async {
  if (!await confirm(
        c,
        'Delete this session?',
        'Its time and notes will be permanently removed.',
      ) ||
      !c.mounted) {
    return false;
  }
  try {
    final db = ref.read(databaseProvider);
    await (db.delete(db.sessions)..where((t) => t.id.equals(s.id))).go();
    return true;
  } catch (e) {
    if (c.mounted) {
      toast(c, 'Could not delete this session: $e');
    }
    return false;
  }
}

Widget sessionTile(
  BuildContext c,
  WidgetRef ref,
  AppData data,
  Session s,
) => OpenContainer(
  closedElevation: 0,
  openElevation: 0,
  closedColor: Theme.of(c).colorScheme.surface,
  openColor: Theme.of(c).colorScheme.surface,
  closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  transitionDuration: Motion.duration(c, 400),
  openBuilder: (c, _) => Scaffold(
    appBar: AppBar(title: const Text('Session detail')),
    body: SessionForm(data: data, session: s, day: s.day),
  ),
  closedBuilder: (c, open) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    onTap: withFeedback(open),
    leading: Icon(s.ended == null ? LucideIcons.timer : LucideIcons.clock3),
    title: Text(sessionDate(data, s)),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${s.kind} · ${clockTime(data, s.started)} — ${s.ended == null ? 'running' : clockTime(data, s.ended!)}${s.note.isEmpty ? '' : '\n${s.note}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (s.note.startsWith('Automatic · '))
          TextButton.icon(
            onPressed: withFeedback(
              () => panel(
                c,
                ActivitySheet(
                  initialTab: 1,
                  conditionName: s.note.substring('Automatic · '.length),
                ),
              ),
            ),
            icon: const Icon(LucideIcons.workflow, size: 14),
            label: const Text('Condition set', style: TextStyle(fontSize: 11)),
          ),
      ],
    ),
    trailing: Text(
      elapsed(durationOf(s)),
      style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 12),
    ),
    onLongPress: s.note.startsWith('Automatic · ')
        ? withFeedback(
            () => panel(
              c,
              ActivitySheet(
                initialTab: 1,
                conditionName: s.note.substring('Automatic · '.length),
              ),
            ),
          )
        : null,
  ),
);
void openQuickAdd(BuildContext c, AppData data, String day, String kind) {
  ActionFeedback.tap();
  if (kind == 'session') {
    panel(c, SessionForm(data: data, day: day));
  } else if (kind == 'rule') {
    panel(c, RuleForm(data: data));
  } else {
    panel(c, EntryForm(data: data, day: day, kind: kind));
  }
}

Future<void> quickAdd(BuildContext c, AppData data, String day) => panel<void>(
  c,
  Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add to ${DateFormat('d MMMM').format(calendarDate(day))}',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        for (final kind in ['session', 'expense', 'income', 'savings', 'rule'])
          spaced(
            OutlinedButton(
              onPressed: withFeedback(() {
                Navigator.pop(c);
                if (kind == 'session') {
                  panel(c, SessionForm(data: data, day: day));
                } else if (kind == 'rule') {
                  panel(c, RuleForm(data: data));
                } else {
                  panel(c, EntryForm(data: data, day: day, kind: kind));
                }
              }),
              child: Text(switch (kind) {
                'session' => 'Add session / log',
                'rule' => 'Add budget rule',
                _ => 'Add $kind',
              }),
            ),
          ),
      ],
    ),
  ),
);
