part of 'screens.dart';

Future<bool> deleteActivityLog(
  BuildContext context,
  AppDatabase db,
  String id,
) async {
  var deleted = false;
  await guarded(context, () async {
    deleted = await db.deleteActivityLog(id) > 0;
    if (deleted && context.mounted) {
      dataToast(context, 'Log', DataAction.deleted);
    }
  });
  return deleted;
}

/// Shared deletion action, including pending state and duplicate-tap protection.
class LogDeleteButton extends StatefulWidget {
  final Future<bool> Function() onDelete;
  const LogDeleteButton({super.key, required this.onDelete});
  @override
  State<LogDeleteButton> createState() => _LogDeleteButtonState();
}

class _LogDeleteButtonState extends State<LogDeleteButton> {
  bool active = false, busy = false;
  Future<void> remove() async {
    if (active) return;
    setState(() => active = true);
    try {
      if (!await confirm(
            context,
            'Delete this log?',
            'This log and its map marker will be permanently removed. Its session or Finance record will be kept.',
          ) ||
          !mounted) {
        return;
      }
      setState(() => busy = true);
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() {
          active = false;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppButton(
    label: 'Delete log',
    onPressed: active ? null : remove,
    busy: busy,
    quiet: true,
    destructive: true,
  );
}

class LogsSheet extends ConsumerStatefulWidget {
  const LogsSheet({super.key});
  @override
  ConsumerState<LogsSheet> createState() => _LogsSheetState();
}

class _LogsSheetState extends ConsumerState<LogsSheet> {
  List<Map<String, dynamic>> lastEvents = [];
  late Stream<List<Map<String, dynamic>>> stream = ref
      .read(databaseProvider)
      .watchActivityLogs();

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
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider).value;
    return PanelContent(
      header: PanelHeading(
        title: 'Activity logs',
        trailing: IconButton(
          tooltip: 'Close',
          onPressed: withFeedback(() => Navigator.pop(context)),
          icon: const Icon(LucideIcons.x, size: 18),
        ),
      ),
      scrollable: true,
      child: data == null ? const SkeletonList() : logs(context, ref, data),
    );
  }

  Widget logs(
    BuildContext c,
    WidgetRef ref,
    AppData data,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: stream,
    builder: (c, snapshot) {
      if (snapshot.hasData) lastEvents = snapshot.data!;
      final events = lastEvents;
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
          if (snapshot.hasError) ...[
            const Text(
              'Could not load activity logs. Your saved records are retained.',
            ),
            AppButton(
              label: 'Retry',
              onPressed: () => setState(
                () => stream = ref.read(databaseProvider).watchActivityLogs(),
              ),
            ),
          ],
          if (!snapshot.hasData && !snapshot.hasError)
            const SkeletonList(scrollable: false),
          if (snapshot.hasData && !snapshot.hasError && events.isEmpty)
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
                key: ValueKey('activity-log-${event['id']}'),
                details: logDetails(event),
                action: LogDeleteButton(
                  onDelete: () => deleteActivityLog(
                    context,
                    ref.read(databaseProvider),
                    event['id'] as String,
                  ),
                ),
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
