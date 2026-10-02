part of 'screens.dart';

class ActivitySheet extends ConsumerStatefulWidget {
  final int initialTab;
  final String? conditionName;
  const ActivitySheet({super.key, this.initialTab = 0, this.conditionName});
  @override
  ConsumerState<ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends ConsumerState<ActivitySheet>
    with WidgetsBindingObserver {
  late int tab = widget.initialTab;
  Map<String, dynamic> status = {};
  final name = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController();
  Map<String, dynamic>? place;
  String? editing;
  double radius = 150;
  String exit = 'continue', kind = 'OJT';
  bool placed = false, busy = false, sourceMode = false, ruleRunning = false;
  final code = TextEditingController();
  bool lastCodeNeedsPlace = true;
  bool get requiresPlace =>
      !sourceMode ||
      code.text.contains('location.inside') ||
      code.text.contains('location.outside');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    code.addListener(() {
      final needs =
          code.text.contains('location.inside') ||
          code.text.contains('location.outside');
      if (mounted && needs != lastCodeNeedsPlace) {
        lastCodeNeedsPlace = needs;
        setState(() {});
      }
    });
    final data = ref.read(dataProvider).value;
    if (data != null && widget.conditionName != null) {
      for (final raw in AutomationSync.config(data)['rules'] as List? ?? []) {
        final rule = Map<String, dynamic>.from(raw as Map);
        if (rule['name'] == widget.conditionName) {
          editing = rule['id'] as String;
          loadSource(rule);
          name.text = rule['name'] as String;
          lat.text = rule['lat'].toString();
          lng.text = rule['lng'].toString();
          radius = (rule['radius'] as num).toDouble();
          exit = rule['else'] as String;
          kind = rule['kind'] as String;
          placed = true;
          place = rule;
          break;
        }
      }
    }
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    name.dispose();
    code.dispose();
    lat.dispose();
    lng.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    await guarded(context, () async {
      final next = await AutomationSync.status();
      next['receipts'] = await NativeSession.channel.invokeMethod<bool>(
        'receiptNotificationsAllowed',
      );
      await AutomationSync.reconcile(ref.read(databaseProvider));
      if (mounted) setState(() => status = next);
    });
  }

  Future<void> toggle(String key, bool value) async {
    ActionFeedback.tap();
    await guarded(context, () async {
      await ref.read(databaseProvider).pref(key, value);
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
      if (key == 'purchaseScanning' && value) {
        await NativeSession.channel.invokeMethod<bool>(
          'receiptNotificationPermission',
        );
        await refresh();
      }
    });
  }

  Future<void> currentPlace() async {
    setState(() => busy = true);
    await guarded(context, () async {
      final allowed =
          await NativeSession.channel.invokeMethod<bool>(
            'locationPermission',
          ) ??
          false;
      if (!allowed) {
        throw StateError(
          'Precise location permission is needed to pick this place.',
        );
      }
      final raw = await NativeSession.channel.invokeMethod<String>(
        'currentLocation',
      );
      final location = Map<String, dynamic>.from(jsonDecode(raw!));
      if (!mounted) return;
      setState(() {
        lat.text = location['lat'].toString();
        lng.text = location['lng'].toString();
        place = location;
        placed = false;
      });
      await refresh();
    });
    if (mounted) setState(() => busy = false);
  }

  void loadSource(Map<String, dynamic> rule) {
    sourceMode = rule['source'] != null;
    code.text =
        rule['source'] as String? ??
        RuleCompiler.visual(
          kind: rule['kind'] as String,
          exit: rule['else'] as String,
        );
    ruleRunning = rule['enabled'] == true;
  }

  Future<void> saveRule(AppData data, {bool run = false}) async {
    if (busy) return;
    setState(() => busy = true);
    await guarded(context, () async {
      final latitude = double.tryParse(lat.text),
          longitude = double.tryParse(lng.text);
      final program = sourceMode ? RuleCompiler.compile(code.text) : null;
      final needsLocation = program == null || program['needsLocation'] == true;
      if (name.text.trim().isEmpty ||
          (needsLocation &&
              (!placed ||
                  latitude == null ||
                  longitude == null ||
                  !latitude.isFinite ||
                  !longitude.isFinite ||
                  latitude.abs() > 90 ||
                  longitude.abs() > 180))) {
        throw StateError(
          'Name a place, enter valid coordinates, then drop it into the condition.',
        );
      }
      if (run &&
          needsLocation &&
          (await AutomationSync.status())['background'] != true) {
        throw StateError(
          'Allow precise location and location all the time before running this rule.',
        );
      }
      final config = AutomationSync.config(data);
      final rules = List<Map<String, dynamic>>.from(
        (config['rules'] as List? ?? []).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );
      final id = editing ?? newId();
      if (editing == null && rules.length >= 100) {
        throw StateError('Up to 100 rules can be saved.');
      }
      rules.removeWhere((r) => r['id'] == id);
      rules.add({
        'id': id,
        'name': name.text.trim(),
        'lat': latitude ?? 0,
        'lng': longitude ?? 0,
        'radius': radius,
        'kind': kind,
        'else': exit,
        'enabled': sourceMode ? run : true,
        if (sourceMode) 'source': code.text,
        'program': ?program,
      });
      config['rules'] = rules;
      if (run && needsLocation) {
        await ref.read(databaseProvider).pref('locationEnabled', true);
      }
      await ref.read(databaseProvider).pref('automation', jsonEncode(config));
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
      if (mounted) {
        setState(() {
          if (sourceMode) {
            editing = id;
            ruleRunning = run;
          } else {
            editing = null;
            placed = false;
            place = null;
            name.clear();
            lat.clear();
            lng.clear();
          }
        });
        toast(
          context,
          run
              ? 'Rule running'
              : sourceMode
              ? 'Rule saved · paused'
              : 'Condition saved',
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> stopRule(AppData data) async {
    if (busy || editing == null) return;
    setState(() => busy = true);
    await guarded(context, () async {
      final config = AutomationSync.config(data);
      for (final raw in config['rules'] as List? ?? []) {
        if (raw['id'] == editing) raw['enabled'] = false;
      }
      await ref.read(databaseProvider).pref('automation', jsonEncode(config));
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
      if (mounted) {
        setState(() => ruleRunning = false);
        toast(context, 'Rule stopped');
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> apps(AppData data) async {
    await guarded(context, () async {
      final installed =
          (await NativeSession.channel.invokeListMethod('notificationApps') ??
                  [])
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList();
      final config = AutomationSync.config(data);
      final selected = Set<String>.from(config['apps'] as List? ?? []);
      if (!mounted) return;
      await panel(
        context,
        StatefulBuilder(
          builder: (c, change) => SizedBox(
            height: MediaQuery.sizeOf(c).height * .6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Scan selected payment apps',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: installed
                        .map(
                          (app) => CheckboxListTile(
                            title: Text(app['name'] as String),
                            subtitle: Text(app['package'] as String),
                            value: selected.contains(app['package']),
                            onChanged: (v) => change(() {
                              v!
                                  ? selected.add(app['package'] as String)
                                  : selected.remove(app['package']);
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: withFeedback(() async {
                      config['apps'] = selected.toList();
                      await ref
                          .read(databaseProvider)
                          .pref('automation', jsonEncode(config));
                      await AutomationSync.configure(
                        await ref.read(databaseProvider).readAll(),
                      );
                      if (c.mounted) Navigator.pop(c);
                    }),
                    child: const Text('Save selected apps'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext c) {
    final data = ref.watch(dataProvider).value;
    if (data == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(c).height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Activity & conditions',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: withFeedback(() => Navigator.pop(c)),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: TextButton(
                    onPressed: withFeedback(() => setState(() => tab = i)),
                    child: Text(
                      i == 0 ? 'Logs' : 'Syntax builder',
                      style: TextStyle(
                        fontWeight: tab == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: tab == i
                            ? Theme.of(c).colorScheme.onSurface
                            : Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(child: tab == 0 ? logs(c, data) : builder(c, data)),
        ],
      ),
    );
  }

  Widget logs(
    BuildContext c,
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
            onChanged: (v) => toggle('activityLogging', v),
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

  Widget builder(BuildContext c, AppData data) {
    final config = AutomationSync.config(data);
    final rules = (config['rules'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    Widget block(String label, Widget content) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Location conditions'),
          subtitle: const Text(
            'Check saved radii and sample location about every 15 minutes',
          ),
          value: data.prefs['locationEnabled'] == 'true',
          onChanged: (v) => toggle('locationEnabled', v),
        ),
        if (status['background'] != true)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: withFeedback(() async {
                  await NativeSession.channel.invokeMethod(
                    'locationPermission',
                  );
                  await refresh();
                }),
                child: const Text('Allow precise location'),
              ),
              OutlinedButton(
                onPressed: withFeedback(
                  () => NativeSession.channel.invokeMethod(
                    'backgroundPermission',
                  ),
                ),
                child: const Text('Allow location all the time'),
              ),
            ],
          ),
        const Text(
          'Android may delay background checks. Location rules require precise location and “Allow all the time”. Other rules work without GPS.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(rule['name'] as String),
                subtitle: Text(
                  rule['source'] != null
                      ? '${rule['enabled'] == true ? 'Running' : 'Paused'} · structured rule'
                      : 'If inside ${rule['radius']} m → clock in\nElse → ${rule['else'] == 'clock_out' ? 'clock out' : 'continue'}',
                ),
                onTap: withFeedback(
                  () => setState(() {
                    editing = rule['id'] as String;
                    loadSource(rule);
                    name.text = rule['name'] as String;
                    lat.text = rule['lat'].toString();
                    lng.text = rule['lng'].toString();
                    radius = (rule['radius'] as num).toDouble();
                    exit = rule['else'] as String;
                    kind = rule['kind'] as String;
                    placed = true;
                    place = rule;
                  }),
                ),
                trailing: IconButton(
                  tooltip: 'Delete condition',
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  onPressed: withFeedback(() async {
                    if (!await confirm(
                          c,
                          'Delete condition?',
                          'Existing sessions stay recorded.',
                        ) ||
                        !c.mounted) {
                      return;
                    }
                    rules.removeWhere((r) => r['id'] == rule['id']);
                    config['rules'] = rules;
                    await ref
                        .read(databaseProvider)
                        .pref('automation', jsonEncode(config));
                    await AutomationSync.configure(
                      await ref.read(databaseProvider).readAll(),
                    );
                  }),
                ),
              ),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Structured syntax'),
          subtitle: const Text(
            'Targets, conditions, actions and completion hints',
          ),
          value: sourceMode,
          onChanged: ruleRunning && sourceMode
              ? null
              : (v) => setState(() {
                  ActionFeedback.tap();
                  sourceMode = v;
                  if (v && code.text.trim().isEmpty) {
                    code.text = RuleCompiler.visual(kind: kind, exit: exit);
                  }
                }),
        ),
        block(
          sourceMode
              ? 'Rule name'
              : editing == null
              ? 'Choose a place'
              : 'Edit condition',
          Column(
            children: [
              spaced(
                TextField(
                  controller: name,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: sourceMode
                        ? 'Rule name'
                        : 'Place name · office, school, shop',
                  ),
                ),
              ),
              if (requiresPlace)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: lat,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lng,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                        ),
                      ),
                    ),
                  ],
                ),
              if (requiresPlace)
                TextButton.icon(
                  onPressed: withFeedback(busy ? null : currentPlace),
                  icon: const Icon(LucideIcons.locateFixed, size: 18),
                  label: Text(
                    busy ? 'Finding location…' : 'Use current location',
                  ),
                ),
            ],
          ),
        ),
        if (requiresPlace)
          LongPressDraggable<bool>(
            data: true,
            feedback: Material(
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(name.text.isEmpty ? 'Selected place' : name.text),
              ),
            ),
            child: ListTile(
              leading: const Icon(LucideIcons.gripVertical),
              title: Text(
                name.text.isEmpty
                    ? 'Drag selected place into If'
                    : 'Drag ${name.text} into If',
              ),
            ),
          ),
        if (requiresPlace)
          block(
            'IF · Location is inside',
            DragTarget<bool>(
              onAcceptWithDetails: (_) => setState(() => placed = true),
              builder: (c, candidates, rejected) => Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(c).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      placed
                          ? 'Within ${radius.round()} m of ${name.text.isEmpty ? 'selected place' : name.text}'
                          : 'Drop a location here',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Slider(
                    value: radius,
                    min: 100,
                    max: 1000,
                    divisions: 18,
                    label: '${radius.round()} m',
                    onChanged: (v) => setState(() => radius = v),
                  ),
                ],
              ),
            ),
          ),
        if (sourceMode)
          Surface(
            padding: const EdgeInsets.all(16),
            child: RuleCodeEditor(
              controller: code,
              settingFields: data.prefs.keys
                  .map((k) => 'settings.$k')
                  .where(
                    (k) =>
                        k != 'settings.automation' &&
                        !k.startsWith('settings.purchaseNotice:') &&
                        !k.startsWith('settings.ruleToast:'),
                  ),
              create: busy
                  ? null
                  : () => setState(() {
                      editing = null;
                      ruleRunning = false;
                      placed = false;
                      place = null;
                      name.clear();
                      lat.clear();
                      lng.clear();
                      code.text = 'target == app {\n  if (app.foreground == true) {\n    app.toast("Rule matched");\n  }\n}';
                    }),
              running: ruleRunning,
              busy: busy,
              run: () => saveRule(data, run: true),
              stop: () => stopRule(data),
            ),
          ),
        if (!sourceMode)
          block(
            'THEN · Clock in',
            selectField('Session type', kind, [
              'OJT',
              'Work',
              'Study',
              'Personal',
            ], (v) => setState(() => kind = v)),
          ),
        if (!sourceMode)
          block(
            'ELSE · Outside the radius',
            selectField(
              'Action',
              exit == 'clock_out' ? 'Clock out' : 'Keep running',
              ['Keep running', 'Clock out'],
              (v) => setState(
                () => exit = v == 'Clock out' ? 'clock_out' : 'continue',
              ),
            ),
          ),
        FilledButton(
          onPressed: withFeedback(
            busy || (sourceMode && ruleRunning) ? null : () => saveRule(data),
          ),
          child: Text(editing == null ? 'Save condition' : 'Update condition'),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Detect purchases'),
          subtitle: const Text(
            'Clear purchase notifications become Budget expenses',
          ),
          value: data.prefs['purchaseScanning'] == 'true',
          onChanged: (v) => toggle('purchaseScanning', v),
        ),
        OutlinedButton(
          onPressed: withFeedback(() => apps(data)),
          child: const Text('Choose payment apps'),
        ),
        if (status['notifications'] != true)
          OutlinedButton(
            onPressed: withFeedback(
              () =>
                  NativeSession.channel.invokeMethod('notificationPermission'),
            ),
            child: const Text('Allow notification access'),
          ),
        if (data.prefs['purchaseScanning'] == 'true' &&
            status['receipts'] != true)
          OutlinedButton(
            onPressed: withFeedback(() async {
              await NativeSession.channel.invokeMethod<bool>(
                'receiptNotificationPermission',
              );
              await refresh();
            }),
            child: const Text('Allow saved-transaction notifications'),
          ),
        const SizedBox(height: 8),
        const Text(
          'Only selected apps are scanned. No OTPs or unrelated notification text are stored. Amounts, merchant labels and locations are used only when available; unclear messages are skipped.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
