import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'app_update.dart';
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
part 'wallets.dart';
part 'wallet_views.dart';
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

Color sessionTypeColor(String kind, bool dark) => switch (kind) {
  'OJT' => dark ? const Color(0xFF7092FF) : const Color(0xFF3E63DD),
  'Work' => dark ? const Color(0xFF54B684) : const Color(0xFF287D55),
  'Study' => dark ? const Color(0xFFA78BE8) : const Color(0xFF7152BD),
  'Personal' => dark ? const Color(0xFFDF9E58) : const Color(0xFFB46A24),
  _ => dark ? const Color(0xFF9AA39C) : const Color(0xFF5E665F),
};

IconData sessionTypeIcon(String kind, {bool running = false}) {
  if (running) return LucideIcons.timer;
  return switch (kind) {
    'OJT' => LucideIcons.briefcase,
    'Work' => LucideIcons.laptop,
    'Study' => LucideIcons.bookOpen,
    'Personal' => LucideIcons.user,
    _ => LucideIcons.clock3,
  };
}

String sessionDurationLabel(int seconds) {
  if (seconds <= 0) return '0m';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remMinutes = minutes % 60;
  return '${hours}h ${remMinutes.toString().padLeft(2, '0')}m';
}

Widget sessionTile(
  BuildContext c,
  WidgetRef ref,
  AppData data,
  Session s, {
  bool selecting = false,
  bool selected = false,
  VoidCallback? onTapOverride,
}) {
  final theme = Theme.of(c);
  final colors = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final running = s.ended == null;
  final accent = running
      ? (dark ? const Color(0xFF55C486) : const Color(0xFF1E8E5A))
      : sessionTypeColor(s.kind, dark);
  final conditionName = s.note.startsWith('Automatic · ')
      ? s.note.substring('Automatic · '.length)
      : null;

  return AnimatedContainer(
    duration: Motion.duration(c, 160),
    curve: Motion.curve,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: selecting && selected
          ? Border.all(color: colors.primary, width: 1.5)
          : null,
    ),
    child: Surface(
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      child: Material(
        color: selecting && selected
            ? colors.primary.withValues(alpha: .06)
            : Colors.transparent,
        child: ListTile(
          horizontalTitleGap: 12,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          onTap: withFeedback(
            onTapOverride ??
                () => panel(c, SessionForm(data: data, session: s, day: s.day)),
          ),
          onLongPress: !selecting && conditionName != null
              ? withFeedback(
                  () => openSyntaxBuilder(c, conditionName: conditionName),
                )
              : null,
          leading: selecting
              ? Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colors.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? colors.primary : colors.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          LucideIcons.check,
                          size: 14,
                          color: colors.onPrimary,
                        )
                      : null,
                )
              : Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: accent.withValues(alpha: .18)),
                  ),
                  child: Icon(
                    sessionTypeIcon(s.kind, running: running),
                    size: 17,
                    color: accent,
                  ),
                ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  sessionDate(data, s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                elapsed(durationOf(s)),
                style: TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: running ? accent : colors.onSurface,
                ),
              ),
              if (!selecting) ...[
                const SizedBox(width: 3),
                Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: colors.onSurfaceVariant.withValues(alpha: .45),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (running) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          s.kind,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${clockTime(data, s.started)} – ${running ? 'Running' : clockTime(data, s.ended!)}',
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 12,
                      color: running ? accent : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (s.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: colors.onSurface.withValues(alpha: .82),
                    ),
                  ),
                ),
              if (conditionName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Material(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(99),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: withFeedback(
                        () =>
                            openSyntaxBuilder(c, conditionName: conditionName),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.workflow, size: 12, color: accent),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Condition set',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void openQuickAdd(BuildContext c, AppData data, String day, String kind) {
  ActionFeedback.tap();
  if (kind == 'session') {
    panel(c, SessionForm(data: data, day: day));
  } else if (kind == 'rule') {
    panel(c, RuleForm(data: data));
  } else if (kind == 'transfer') {
    if (data.walletMethods.length < 2) {
      toast(c, 'Add another wallet first to transfer money.', error: true);
      return;
    }
    panel(c, WalletTransferSheet(data: data, initialDay: day));
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
        for (final kind in [
          'session',
          'expense',
          'income',
          'savings',
          if (data.walletMethods.length >= 2) 'transfer',
          'rule',
        ])
          spaced(
            OutlinedButton(
              onPressed: withFeedback(() {
                Navigator.pop(c);
                openQuickAdd(c, data, day, kind);
              }),
              child: Text(switch (kind) {
                'session' => 'Add session / log',
                'transfer' => 'Transfer money',
                'rule' => 'Add budget rule',
                _ => 'Add $kind',
              }),
            ),
          ),
      ],
    ),
  ),
);
