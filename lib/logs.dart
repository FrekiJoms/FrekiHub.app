part of 'screens.dart';

class LogsSheet extends ConsumerWidget {
  const LogsSheet({super.key});

  Future<void> toggle(BuildContext context, WidgetRef ref, bool value) async {
    ActionFeedback.tap();
    await guarded(
      context,
      () async {
        await ref.read(databaseProvider).pref('activityLogging', value);
        await AutomationSync.configure(
          await ref.read(databaseProvider).readAll(),
        );
      },
      success: 'Activity logging ${value ? 'enabled' : 'disabled'}',
      successIcon: value ? DataAction.enabled.icon : DataAction.disabled.icon,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider).value;
    return PanelContent(
      header: const PanelHeading(title: 'Activity logs'),
      scrollable: true,
      child: data == null ? const SkeletonList() : logs(context, ref, data),
    );
  }

  Widget logs(BuildContext c, WidgetRef ref, AppData data) =>
      StreamBuilder<List<Map<String, dynamic>>>(
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
              if (!snapshot.hasData) const SkeletonList(scrollable: false),
              if (snapshot.hasData && events.isEmpty)
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
                  child: LogRow(
                    title: event['title'] as String,
                    dateTime: DateFormat('d MMM yyyy, HH:mm:ss').format(time),
                  ),
                );
              }),
            ],
          );
        },
      );
}
