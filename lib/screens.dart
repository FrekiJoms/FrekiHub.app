import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoPicker,
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        DatePickerDateOrder,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart' hide Projection;
import 'package:latlong2/latlong.dart';
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
import 'map_records.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
part 'today.dart';
part 'calendar.dart';
part 'map.dart';
part 'history.dart';
part 'budget.dart';
part 'settings.dart';
part 'forms.dart';
part 'pickers.dart';
part 'logs.dart';
part 'syntax_builder.dart';
part 'controls.dart';
part 'rule_editor.dart';

Future<T> saveWithLocation<T>(
  BuildContext context,
  AppDatabase db,
  Future<T> Function() save,
) => RecordLocation.commit(
  db,
  save,
  permission: () async =>
      context.mounted &&
      await PermissionHints.request<bool>(
            context,
            'locationPermission',
            hint: const PermissionHintSpec(
              title: 'Save where this happened',
              intro: 'Attach your current position to this activity.',
              benefit: 'Find your records on Map',
              detail: 'Session actions and Finance saves can include one fresh location sample.',
              control: 'Declining still saves your record without a location. Activity logging and location must both be enabled.',
              next: 'Allow precise location while using the app.',
              action: 'Allow precise location',
              icon: LucideIcons.mapPin,
            ),
          ) ==
          true,
);

Future<void> guarded(
  BuildContext c,
  Future<void> Function() operation, {
  String? success,
  IconData? successIcon,
}) async {
  try {
    await operation();
    if (c.mounted && success != null) {
      toast(c, success, icon: successIcon);
    }
  } catch (e) {
    if (c.mounted) {
      toast(
        c,
        e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : 'Could not complete this action. Try again.',
        error: true,
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
  return displayDate(d, calendarDate(s.day));
}

String displayDate(AppData d, DateTime date) {
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

/// Decode display metadata once per row without assuming optional fields exist.
String logDetails(Map<String, dynamic> event) {
  final extra = MapRecord.decode(event['details']);
  final position = MapRecord.decode(extra['position'] ?? extra);
  final lines = <String>[
    'Action: ${event['action'] ?? 'Activity'}',
    'Location: ${event['location'] ?? 'Not recorded'}',
  ];
  if (extra['amount'] != null) {
    final currency = extra['currency'];
    lines.add(
      'Amount: ${extra['amount'] is int && currency is String && currencyDigits.containsKey(currency) ? money(extra['amount'] as int, currency) : '${extra['amount']} ${currency ?? ''}'}',
    );
  }
  for (final field in {
    'kind': 'Session type',
    'merchant': 'Merchant',
    'method': 'Payment method',
    'source': 'Source',
    'reference': 'Reference',
    'note': 'Note',
  }.entries) {
    final value = extra[field.key];
    if (value != null && value.toString().isNotEmpty) {
      lines.add('${field.value}: $value');
    }
  }
  if (position['lat'] != null && position['lng'] != null) {
    lines.add('Coordinates: ${position['lat']}, ${position['lng']}');
  }
  if (position['accuracy'] != null) {
    lines.add('Accuracy: ±${position['accuracy']} m');
  }
  if (position['locationTime'] is int) {
    lines.add(
      'Sampled: ${DateFormat('d MMM yyyy, HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(position['locationTime'] as int))}',
    );
  }
  const shown = {
    'position',
    'lat',
    'lng',
    'accuracy',
    'locationTime',
    'amount',
    'currency',
    'kind',
    'merchant',
    'method',
    'source',
    'reference',
    'note',
    'id',
    'title',
    'time',
    'location',
    'action',
  };
  for (final field in extra.entries.where((e) => !shown.contains(e.key))) {
    lines.add('${field.key}: ${field.value}');
  }
  return lines.join('\n');
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
    final deleted = await (db.delete(
      db.sessions,
    )..where((t) => t.id.equals(s.id))).go();
    if (c.mounted && deleted > 0) {
      dataToast(c, 'Session', DataAction.deleted);
    }
    return true;
  } catch (e) {
    if (c.mounted) {
      toast(c, 'Could not delete this session. Try again.', error: true);
    }
    return false;
  }
}

Widget sessionTile(
  BuildContext c,
  WidgetRef ref,
  AppData data,
  Session s,
) => Surface(
  padding: EdgeInsets.zero,
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    onTap: withFeedback(
      () => panel(c, SessionForm(data: data, session: s, day: s.day)),
    ),
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
              () => openSyntaxBuilder(
                c,
                conditionName: s.note.substring('Automatic · '.length),
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
            () => openSyntaxBuilder(
              c,
              conditionName: s.note.substring('Automatic · '.length),
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
  PanelContent(
    header: Text(
      'Add to ${DateFormat('d MMMM').format(calendarDate(day))}',
      style: Theme.of(c).textTheme.titleLarge,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
