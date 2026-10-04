part of 'screens.dart';

class OverlayPermissionHint extends StatelessWidget {
  final bool allowed;
  const OverlayPermissionHint({super.key, required this.allowed});
  @override
  Widget build(BuildContext context) => PanelContent(
    header: const PanelHeading(
      title: 'Confirm wherever you are',
      leading: Chrome(
        padding: EdgeInsets.all(10),
        child: Icon(LucideIcons.layers, size: 20),
      ),
    ),
    footer: PanelActions(
      children: [
        AppButton(
          label: allowed ? 'Manage access' : 'Allow overlay',
          onPressed: () => Navigator.pop(context, true),
        ),
        AppButton(
          label: 'Not now',
          secondary: true,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          allowed
              ? 'Overlay access is enabled.'
              : 'A final check, without leaving your current app.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(LucideIcons.notebookPen),
          title: Text('Review before ending'),
          subtitle: Text(
            'Clock out opens a confirmation and an editable session note over your current app.',
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(LucideIcons.timer),
          title: Text('You stay in control'),
          subtitle: Text(
            'It appears only when you tap Clock out. Your timer keeps running until you confirm.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'On the next screen, ${allowed ? 'manage' : 'enable'} Display over other apps for FrekiHub.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class SettingsScreen extends ConsumerStatefulWidget {
  final AppData data;
  const SettingsScreen({super.key, required this.data});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool busy = false;
  Offset themeOrigin = const Offset(160, 230);
  Future<void> changeTheme(String mode) async {
    ActionFeedback.tap(transition: true);
    await ThemeReveal.change(
      context,
      themeOrigin,
      () => ref.read(databaseProvider).pref('theme', mode),
    );
  }

  Future<void> manage(String key, List<String> initial) =>
      panel(context, _ManageList(setting: key, initial: initial));
  Future<void> overlayPermission() => guarded(context, () async {
    final allowed =
        await NativeSession.channel.invokeMethod<bool>('overlayAllowed') ??
        false;
    if (!mounted) return;
    final accepted = await panel<bool>(
      context,
      OverlayPermissionHint(allowed: allowed),
    );
    if (accepted == true && mounted) {
      await NativeSession.channel.invokeMethod('overlayPermission');
    }
  });
  Future<void> notificationSounds() async {
    final category = await panel<String>(
      context,
      const _ChoiceSheet(
        title: 'Notification sounds',
        selected: '',
        values: ['Reminders', 'Saved transactions', 'Running sessions'],
      ),
    );
    if (category == null || !mounted) return;
    const categories = {
      'Reminders': 'reminders',
      'Saved transactions': 'transactions',
      'Running sessions': 'sessions',
    };
    await guarded(context, () async {
      await NativeSession.channel.invokeMethod(
        'notificationSoundSettings',
        categories[category],
      );
    });
  }

  Future<void> backup() async {
    setState(() => busy = true);
    await guarded(context, () async {
      final source = await ref.read(databaseProvider).backup();
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/frekihub-${dayKey(DateTime.now())}.json',
      );
      await file.writeAsString(source, flush: true);
      if (!mounted) {
        return;
      }
      final render = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'FrekiHub backup',
          sharePositionOrigin: render.localToGlobal(Offset.zero) & render.size,
        ),
      );
    });
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    if (busy) return;
    setState(() => busy = true);
    List<PlatformFile> picked = [];
    await guarded(context, () async {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    });
    if (mounted) setState(() => busy = false);
    if (picked.isEmpty || !mounted) {
      return;
    }
    if (!await confirm(
      context,
      'Replace data with this backup?',
      'Current records and settings will be replaced. Export a backup first if you need to keep them.',
      action: 'Restore',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => busy = true);
    await guarded(context, () async {
      final file = picked.single;
      if ((await file.length() ?? 0) > 20 * 1024 * 1024) {
        throw const FormatException('Backup exceeds the 20 MB limit.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Backup exceeds the 20 MB limit.');
      }
      await ref.read(databaseProvider).restore(utf8.decode(bytes));
      await NativeSession.channel.invokeMethod('automationReset');
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
      await NativeSession.stop();
      final running = (await ref.read(databaseProvider).readAll()).running;
      if (running != null) {
        await NativeSession.start(running);
      }
    }, success: 'Backup restored');
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> clear() async {
    final typed = TextEditingController();
    final approved = await panel<bool>(
      context,
      StatefulBuilder(
        builder: (c, setLocal) => PanelContent(
          header: Text(
            'Clear everything?',
            style: Theme.of(c).textTheme.titleLarge,
          ),
          footer: PanelActions(
            children: [
              AppButton(
                label: 'Clear all data',
                onPressed: typed.text == 'DELETE'
                    ? () => Navigator.pop(c, true)
                    : null,
              ),
              AppButton(
                label: 'Cancel',
                secondary: true,
                onPressed: () => Navigator.pop(c, false),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'All hours, transactions, rules, and settings will be removed. This cannot be undone. Type DELETE to confirm.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: typed,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(labelText: 'Confirmation'),
              ),
            ],
          ),
        ),
      ),
    );
    typed.dispose();
    if (approved == true && mounted) {
      await guarded(context, () async {
        await ref.read(databaseProvider).clear();
        await NativeSession.channel.invokeMethod('automationReset');
        await NativeSession.stop();
      }, success: 'All data cleared');
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final theme = d.prefs['theme'] ?? 'system';
    return PageBody(
      title: 'Settings.',
      subtitle: 'Preferences & storage',
      children: [
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.activity),
                title: const Text('Activity logs'),
                subtitle: const Text('Time, location and recorded actions'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(() => panel(c, const ActivitySheet())),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.workflow),
                title: const Text('Conditions & automation'),
                subtitle: const Text('If a condition matches, run an action'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(
                  () => panel(c, const ActivitySheet(initialTab: 1)),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.bell),
                title: const Text('Saved-transaction notifications'),
                subtitle: const Text(
                  'Confirm amounts and merchants after saving',
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(
                  () => guarded(c, () async {
                    final allowed = await NativeSession.channel
                        .invokeMethod<bool>('receiptNotificationPermission');
                    if (allowed == true) {
                      await AutomationSync.reconcile(
                        ref.read(databaseProvider),
                      );
                      if (c.mounted) {
                        toast(c, 'Saved-transaction notifications enabled');
                      }
                    } else if (c.mounted) {
                      toast(
                        c,
                        'Allow FrekiHub notifications in Android settings',
                      );
                    }
                  }),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.volume2),
                title: const Text('Notification sounds'),
                subtitle: const Text(
                  'Choose a tone or Silent for each notification type',
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(notificationSounds),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.layers),
                title: const Text('Confirm over other apps'),
                subtitle: const Text(
                  'Review your session before clocking out from Dynamic Island',
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(overlayPermission),
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('Appearance'),
              const SizedBox(height: 20),
              Listener(
                onPointerDown: (event) => themeOrigin = event.position,
                child: GlassSegmentedControl(
                  useOwnLayer: true,
                  segments: const [
                    GlassSegment(label: 'Light'),
                    GlassSegment(label: 'Dark'),
                    GlassSegment(label: 'System'),
                  ],
                  selectedIndex: ['light', 'dark', 'system'].indexOf(theme),
                  onSegmentSelected: (i) =>
                      changeTheme(['light', 'dark', 'system'][i]),
                ),
              ),
              const SizedBox(height: 16),
              selectField(
                'Display currency',
                d.currency,
                currencyDigits.keys.toList(),
                (v) async {
                  await ref.read(databaseProvider).pref('currency', v);
                  if (c.mounted) {
                    toast(
                      c,
                      'Showing $v records. Existing amounts retain their currency.',
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Finance totals and charts use this currency. Calendar records keep their original currency.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.tags, size: 20),
                title: const Text('Categories'),
                subtitle: Text('${d.categories.length} categories'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(() => manage('categories', d.categories)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.creditCard, size: 20),
                title: const Text('Payment methods'),
                subtitle: Text('${d.methods.length} ways to pay'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: withFeedback(() => manage('methods', d.methods)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(LucideIcons.volume2, size: 20),
                title: const Text('Sound effects'),
                subtitle: const Text(
                  'Soft clicks, transitions, and timer cues',
                ),
                value: d.prefs['sound'] == 'true',
                onChanged: (v) {
                  ActionFeedback.soundEnabled = v;
                  ActionFeedback.tap();
                  ref.read(databaseProvider).pref('sound', v);
                },
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading('Backup & storage'),
              const SizedBox(height: 12),
              const Text(
                'Save a backup somewhere safe. Removing the app removes the data stored on this phone.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: withFeedback(busy ? null : backup),
                icon: const Icon(LucideIcons.download, size: 18),
                label: const Text('Export everything'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: withFeedback(busy ? null : restore),
                icon: const Icon(LucideIcons.upload, size: 18),
                label: const Text('Restore a backup'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: withFeedback(busy ? null : clear),
                child: Text(
                  'Clear all data',
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FrekiHub',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'A personal place for your time and money.\nVersion 1.0.0 · Local storage · No account',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManageList extends ConsumerStatefulWidget {
  final String setting;
  final List<String> initial;
  const _ManageList({required this.setting, required this.initial});
  @override
  ConsumerState<_ManageList> createState() => _ManageListState();
}

class _ManageListState extends ConsumerState<_ManageList> {
  late List<String> items;
  final name = TextEditingController();
  bool saving = false;
  @override
  void initState() {
    super.initState();
    items = [...widget.initial];
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save(List<String> next, {bool clearName = false}) async {
    if (saving) return;
    setState(() => saving = true);
    await guarded(context, () async {
      await ref.read(databaseProvider).pref(widget.setting, jsonEncode(next));
      if (!mounted) return;
      setState(() {
        items = next;
        if (clearName) name.clear();
      });
    });
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext c) => PanelContent(
    header: Column(
      children: [
        Text(
          widget.setting == 'categories' ? 'Categories' : 'Payment methods',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: name,
          decoration: InputDecoration(
            labelText: 'Add a name',
            suffixIcon: IconButton(
              tooltip: 'Add',
              onPressed: withFeedback(
                saving
                    ? null
                    : () async {
                        final value = name.text.trim();
                        if (value.isEmpty ||
                            items.any(
                              (s) => s.toLowerCase() == value.toLowerCase(),
                            )) {
                          toast(c, 'Enter a new, unique name.', error: true);
                          return;
                        }
                        await save([...items, value], clearName: true);
                      },
              ),
              icon: const Icon(LucideIcons.plus),
            ),
          ),
        ),
      ],
    ),
    footer: AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
    scrollable: true,
    child: ListView(
      children: items
          .map(
            (item) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(item),
              trailing: IconButton(
                tooltip: 'Remove $item',
                onPressed: withFeedback(
                  saving || items.length <= 1
                      ? null
                      : () async {
                          await save(items.where((s) => s != item).toList());
                        },
                ),
                icon: const Icon(LucideIcons.x, size: 18),
              ),
            ),
          )
          .toList(),
    ),
  );
}
