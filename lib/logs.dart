part of 'screens.dart';

class LogsSheet extends ConsumerWidget {
  const LogsSheet({super.key});

  Future<void> toggle(BuildContext context, WidgetRef ref, bool value) async {
    ActionFeedback.tap();
    await guarded(context, () async {
      await ref.read(databaseProvider).pref('activityLogging', value);
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider).value;
    return PanelContent(
      header: const PanelHeading(title: 'Activity logs'),
      scrollable: true,
      child: data == null
          ? const Center(child: CircularProgressIndicator())
          : logs(context, ref, data),
    );
  }

  Widget logs(
    BuildContext c,
    WidgetRef ref,
    AppData data,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: ref.read(databaseProvider).watchActivityLogs(),
    builder: (c, snapshot) {
      final events = snapshot.data ?? [];
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activity logging'),
            subtitle: const Text(
              'Store actions and location snapshots locally',
            ),
            value: data.prefs['activityLogging'] == 'true',
            onChanged: (v) => toggle(c, ref, v),
          ),
          if (events.isEmpty)
            const EmptyState(
              'No activity yet',
              'Enable logging to record new actions.',
              LucideIcons.activity,
            ),
          ...events.map((event) {
            final time = DateTime.fromMillisecondsSinceEpoch(
              event['time'] as int,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Theme.of(c).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  leading: Icon(
                    event['action'] == 'location'
                        ? LucideIcons.mapPin
                        : event['action'] == 'expense' ||
                              event['action'] == 'purchase'
                        ? LucideIcons.shoppingBag
                        : LucideIcons.clock3,
                    size: 20,
                  ),
                  title: Text(event['title'] as String),
                  subtitle: Text(
                    '${event['location']} · ${DateFormat('d MMM, HH:mm').format(time)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        activityDetails(event),
                        style: Theme.of(c).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    },
  );
  String activityDetails(Map<String, dynamic> event) {
    Map<String, dynamic> extra = {};
    try {
      extra = Map<String, dynamic>.from(jsonDecode(event['details'] as String));
    } catch (_) {}
    Map<String, dynamic> position = extra;
    if (extra['position'] is String) {
      try {
        position = Map<String, dynamic>.from(
          jsonDecode(extra['position'] as String),
        );
      } catch (_) {}
    }
    final lines = <String>[
      DateFormat('EEEE, d MMMM yyyy · HH:mm:ss')
          .format(DateTime.fromMillisecondsSinceEpoch(event['time'] as int)),
      'Location: ${event['location']}',
    ];
    if (extra['amount'] != null && extra['currency'] is String) {
      final amount = extra['amount'] is int
          ? extra['amount'] as int
          : parseMoney(extra['amount'].toString(), extra['currency'] as String);
      lines.add('Amount: ${money(amount, extra['currency'] as String)}');
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
      lines.add(
        'Location accuracy: ±${(position['accuracy'] as num).round()} m',
      );
    }
    if (position['locationTime'] is int) {
      lines.add(
        'Location sampled: ${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(position['locationTime'] as int))}',
      );
    }
    return lines.join('\n');
  }
}
