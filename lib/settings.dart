part of 'screens.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final AppData data;
  const SettingsScreen({super.key, required this.data});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool busy = false;
  String? busyAction;
  Offset themeOrigin = const Offset(160, 230);
  Future<void> changeTheme(String mode) async {
    ActionFeedback.tap(transition: true);
    await guarded(
      context,
      () => ThemeReveal.change(
        context,
        themeOrigin,
        () => ref.read(databaseProvider).pref('theme', mode),
      ),
      success: 'Theme updated',
      successIcon: DataAction.updated.icon,
    );
  }

  Future<void> manage(String key, List<String> initial) =>
      panel(context, _ManageList(setting: key, initial: initial));
  Future<void> overlayPermission() => guarded(context, () async {
    await PermissionHints.request<void>(
      context,
      'overlayPermission',
      manage: true,
    );
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
    setState(() {
      busy = true;
      busyAction = 'backup';
    });
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
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'FrekiHub backup',
          sharePositionOrigin: render.localToGlobal(Offset.zero) & render.size,
        ),
      );
      if (mounted && result.status == ShareResultStatus.success) {
        dataToast(context, 'Backup', DataAction.exported);
      } else if (mounted && result.status == ShareResultStatus.unavailable) {
        toast(context, 'Backup prepared', icon: DataAction.exported.icon);
      }
    });
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    if (busy) return;
    setState(() {
      busy = true;
      busyAction = 'restore';
    });
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
    setState(() {
      busy = true;
      busyAction = 'restore';
    });
    await guarded(
      context,
      () async {
        final file = picked.single;
        if ((await file.length() ?? 0) > maxBackupBytes) {
          throw const FormatException(
            'Backup exceeds the supported 128 MB limit.',
          );
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > maxBackupBytes) {
          throw const FormatException(
            'Backup exceeds the supported 128 MB limit.',
          );
        }
        await ref.read(databaseProvider).restore(utf8.decode(bytes));
        await NativeSession.channel.invokeMethod('automationReset');
        await AutomationSync.configure(
          await ref.read(databaseProvider).readAll(),
        );
        await NativeSession.stop();
        final running = (await ref.read(databaseProvider).readAll()).running;
        if (running != null && mounted) {
          if (!await NativeSession.cache(running) || !mounted) return;
          await PermissionHints.perform<bool>(
            context,
            'start',
            () => NativeSession.start(running),
          );
        }
      },
      success: 'Backup restored',
      successIcon: DataAction.restored.icon,
    );
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
      await guarded(
        context,
        () async {
          await ref.read(databaseProvider).clear();
          await NativeSession.channel.invokeMethod('automationReset');
          await NativeSession.stop();
        },
        success: 'All data cleared',
        successIcon: DataAction.deleted.icon,
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final theme = d.prefs['theme'] ?? 'system';
    return PageBody(
      title: 'SETTINGS',
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
                onTap: withFeedback(() => panel(c, const LogsSheet())),
              ),
            ],
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.workflow),
            title: const Text('Syntax builder'),
            subtitle: const Text('Conditions, rules & automation'),
            trailing: const Icon(LucideIcons.arrowUpRight, size: 18),
            onTap: withFeedback(() => openSyntaxBuilder(c)),
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
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
                    final allowed = await PermissionHints.request<bool>(
                      c,
                      'receiptNotificationPermission',
                      manage: true,
                    );
                    if (allowed == null) return;
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
                  await guarded(c, () async {
                    await ref.read(databaseProvider).pref('currency', v);
                    if (c.mounted) {
                      toast(
                        c,
                        'Showing $v records. Existing amounts retain their currency.',
                        icon: DataAction.updated.icon,
                      );
                    }
                  });
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
                onChanged: (v) async {
                  ActionFeedback.tap();
                  await guarded(
                    c,
                    () async {
                      await ref.read(databaseProvider).pref('sound', v);
                      ActionFeedback.soundEnabled = v;
                    },
                    success: 'Sound effects ${v ? 'enabled' : 'disabled'}',
                    successIcon: v
                        ? DataAction.enabled.icon
                        : DataAction.disabled.icon,
                  );
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
                label: SkeletonValue(
                  loading: busy && busyAction == 'backup',
                  semanticsLabel: 'Exporting backup',
                  child: const Text('Export everything'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: withFeedback(busy ? null : restore),
                icon: const Icon(LucideIcons.upload, size: 18),
                label: SkeletonValue(
                  loading: busy && busyAction == 'restore',
                  semanticsLabel: 'Restoring backup',
                  child: const Text('Restore a backup'),
                ),
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
                'A personal place for your time and money.\nVersion 1.5.5 · Local storage · No account',
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
  String? savingItem;
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
    final previous = [...items];
    final removed = previous.where((item) => !next.contains(item)).toList();
    setState(() {
      saving = true;
      savingItem = clearName
          ? null
          : previous.firstWhere(
              (item) => !next.contains(item),
              orElse: () => '',
            );
      items = next;
      if (clearName) name.clear();
    });
    var committed = false;
    await guarded(context, () async {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        await db.pref(widget.setting, jsonEncode(next));
        if (widget.setting == 'methods') {
          final prefs = await db.readPreferences();
          final data = AppData(const [], const [], const [], prefs);
          final hidden = {...data.hiddenWallets};
          for (final item in removed) {
            hidden.add(item.trim().toLowerCase());
          }
          for (final item in next) {
            hidden.remove(item.trim().toLowerCase());
          }
          await db.pref('hiddenWallets', jsonEncode(hidden.toList()));
          final order = List<String>.from(
            jsonDecode(prefs['walletOrder'] ?? '[]') as List,
          );
          var orderChanged = false;
          for (final item in next) {
            if (!order.contains(item)) {
              order.add(item);
              orderChanged = true;
            }
          }
          if (removed.isNotEmpty) {
            order.removeWhere((w) => removed.contains(w));
            orderChanged = true;
            final config = AutomationSync.config(data);
            final apps = Set<String>.from(config['apps'] as List? ?? []);
            var appsChanged = false;
            for (final item in removed) {
              final pkg = prefs['wallet:$item:package'];
              if (pkg != null && apps.remove(pkg)) {
                appsChanged = true;
              }
            }
            if (appsChanged) {
              config['apps'] = apps.toList();
              await db.pref('automation', jsonEncode(config));
            }
          }
          if (orderChanged) {
            await db.pref('walletOrder', jsonEncode(order));
          }
        }
      });
      committed = true;
      if (widget.setting == 'methods') {
        unawaited(
          db.readAll().then(AutomationSync.configure).catchError((Object _) {}),
        );
      }
      if (!mounted) return;
      dataToast(
        context,
        widget.setting == 'categories' ? 'Category' : 'Payment method',
        clearName ? DataAction.saved : DataAction.deleted,
      );
    });
    if (mounted) {
      setState(() {
        saving = false;
        savingItem = null;
        if (!committed) items = previous;
      });
    }
  }

  Future<void> _pickInstalledApp() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final installed =
          (await NativeSession.channel.invokeListMethod('notificationApps') ??
                  [])
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList();
      if (!mounted) return;
      setState(() => saving = false);
      var query = '';
      final picked = await panel<Map<String, dynamic>>(
        context,
        StatefulBuilder(
          builder: (c, setLocal) {
            final filtered = query.trim().isEmpty
                ? installed
                : installed.where((app) {
                    final n = (app['name'] as String? ?? '').toLowerCase();
                    final p = (app['package'] as String? ?? '').toLowerCase();
                    final q = query.trim().toLowerCase();
                    return n.contains(q) || p.contains(q);
                  }).toList();
            return PanelContent(
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PanelHeading(title: 'Pick payment app'),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setLocal(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Search installed apps',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                ],
              ),
              footer: AppButton(
                label: 'Cancel',
                secondary: true,
                onPressed: () => Navigator.pop(c),
              ),
              scrollable: true,
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final app = filtered[i];
                  final appName = (app['name'] as String? ?? '').trim();
                  final pkg = (app['package'] as String? ?? '').trim();
                  final added = items.any(
                    (s) => s.toLowerCase() == appName.toLowerCase(),
                  );
                  return ListTile(
                    title: Text(appName),
                    subtitle: Text(
                      pkg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: added
                        ? const Icon(LucideIcons.check, size: 18)
                        : null,
                    onTap: () => Navigator.pop(c, app),
                  );
                },
              ),
            );
          },
        ),
      );
      if (picked == null || !mounted) return;
      final appName = (picked['name'] as String? ?? '').trim();
      final pkg = (picked['package'] as String? ?? '').trim();
      if (appName.isEmpty || pkg.isEmpty) return;

      setState(() => saving = true);
      final db = ref.read(databaseProvider);
      final nextMethods =
          items.any((s) => s.toLowerCase() == appName.toLowerCase())
          ? items
          : [...items, appName];
      await db.transaction(() async {
        final data = await db.readAll();
        final hidden = {...data.hiddenWallets}..remove(appName.toLowerCase());
        await db.pref('methods', jsonEncode(nextMethods));
        await db.pref('hiddenWallets', jsonEncode(hidden.toList()));
        final order = List<String>.from(
          jsonDecode(data.prefs['walletOrder'] ?? '[]') as List,
        );
        if (!order.contains(appName)) {
          order.add(appName);
          await db.pref('walletOrder', jsonEncode(order));
        }
        await db.pref('wallet:$appName:package', pkg);
        await db.pref('wallet:$appName:style', WalletSkin.byName(appName).id);
        final config = AutomationSync.config(data);
        final apps = Set<String>.from(config['apps'] as List? ?? []);
        apps.add(pkg);
        config['apps'] = apps.toList();
        await db.pref('automation', jsonEncode(config));
        await db.pref('purchaseScanning', true);
      });
      await AutomationSync.configure(await db.readAll());
      if (mounted) {
        await PermissionHints.request<bool>(context, 'notificationPermission');
      }
      if (!mounted) return;
      setState(() {
        items = nextMethods;
        saving = false;
      });
      dataToast(context, 'Payment method', DataAction.saved);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, 'Could not load installed apps.', error: true);
      }
    }
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
              icon: SkeletonValue(
                loading: saving && savingItem == null,
                semanticsLabel: 'Saving list item',
                child: const Icon(LucideIcons.plus),
              ),
            ),
          ),
        ),
        if (widget.setting == 'methods') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: withFeedback(saving ? null : _pickInstalledApp),
              icon: const Icon(LucideIcons.smartphone, size: 18),
              label: const Text('Pick installed app'),
            ),
          ),
        ],
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
                icon: SkeletonValue(
                  loading: saving && savingItem == item,
                  semanticsLabel: 'Removing $item',
                  child: const Icon(LucideIcons.x, size: 18),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}
