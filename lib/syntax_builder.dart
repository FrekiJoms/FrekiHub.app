part of 'screens.dart';

Future<void> openSyntaxBuilder(BuildContext context, {String? conditionName}) =>
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Motion.duration(context),
        reverseTransitionDuration: Motion.duration(context, 150),
        pageBuilder: (context, animation, secondaryAnimation) =>
            SyntaxBuilderScreen(conditionName: conditionName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: animation.drive(CurveTween(curve: Motion.curve)),
              child: child,
            ),
      ),
    );

class SyntaxBuilderScreen extends ConsumerStatefulWidget {
  final String? conditionName;
  const SyntaxBuilderScreen({super.key, this.conditionName});
  @override
  ConsumerState<SyntaxBuilderScreen> createState() =>
      _SyntaxBuilderScreenState();
}

class _SyntaxBuilderScreenState extends ConsumerState<SyntaxBuilderScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  final name = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController();
  Map<String, dynamic>? place;
  String? editing;
  double radius = 150;
  String exit = 'continue', kind = 'OJT';
  bool placed = false, busy = false, sourceMode = false, ruleRunning = false;
  bool _appliedInitialCondition = false;
  final code = TextEditingController();
  bool lastCodeNeedsPlace = false;

  bool get requiresPlace => !sourceMode || RuleCompiler.usesLocation(code.text);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final data = ref.read(dataProvider).value;
    if (data != null && widget.conditionName != null) {
      _appliedInitialCondition = true;
      _selectConditionByName(data, widget.conditionName!);
    }
    lastCodeNeedsPlace = RuleCompiler.usesLocation(code.text);
    code.addListener(_onCodeChanged);
    unawaited(refresh());
  }

  void _onCodeChanged() {
    final needs = RuleCompiler.usesLocation(code.text);
    if (mounted && needs != lastCodeNeedsPlace) {
      lastCodeNeedsPlace = needs;
      setState(() {});
    }
  }

  void _selectConditionByName(AppData data, String targetName) {
    for (final raw in AutomationSync.config(data)['rules'] as List? ?? []) {
      final rule = Map<String, dynamic>.from(raw as Map);
      if (rule['name'] == targetName) {
        _applyRuleToDraft(rule);
        break;
      }
    }
  }

  void _applyRuleToDraft(Map<String, dynamic> rule) {
    editing = rule['id'] as String?;
    sourceMode = rule['source'] != null;
    final ruleKind = (rule['kind'] as String?) ?? 'OJT';
    final ruleExit = (rule['else'] as String?) ?? 'continue';
    code.text =
        rule['source'] as String? ??
        RuleCompiler.visual(
          kind: const ['OJT', 'Work', 'Study', 'Personal'].contains(ruleKind)
              ? ruleKind
              : 'OJT',
          exit: ruleExit,
        );
    ruleRunning = sourceMode && rule['enabled'] == true;
    name.text = (rule['name'] as String?) ?? '';
    final ruleLat = (rule['lat'] as num?)?.toDouble() ?? 0;
    final ruleLng = (rule['lng'] as num?)?.toDouble() ?? 0;
    final hasCoords = ruleLat != 0 || ruleLng != 0 || !sourceMode;
    lat.text = hasCoords ? ruleLat.toString() : '';
    lng.text = hasCoords ? ruleLng.toString() : '';
    radius = ((rule['radius'] as num?)?.toDouble() ?? 150).clamp(100, 1000);
    exit = ruleExit == 'clock_out' ? 'clock_out' : 'continue';
    kind = const ['OJT', 'Work', 'Study', 'Personal'].contains(ruleKind)
        ? ruleKind
        : 'OJT';
    placed = hasCoords;
    place = rule;
    lastCodeNeedsPlace = RuleCompiler.usesLocation(code.text);
  }

  void _resetDraft({bool? keepSourceMode}) {
    final nextSourceMode = keepSourceMode ?? sourceMode;
    editing = null;
    ruleRunning = false;
    placed = false;
    place = null;
    radius = 150;
    kind = 'OJT';
    exit = 'continue';
    sourceMode = nextSourceMode;
    name.clear();
    lat.clear();
    lng.clear();
    code.text = nextSourceMode
        ? 'target == app {\n  if (app.foreground == true) {\n    app.toast("Rule matched");\n  }\n}'
        : '';
    lastCodeNeedsPlace = RuleCompiler.usesLocation(code.text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    code.removeListener(_onCodeChanged);
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
      await AutomationSync.reconcile(ref.read(databaseProvider));
      final next = await AutomationSync.status();
      next['receipts'] = await NativeSession.channel.invokeMethod<bool>(
        'receiptNotificationsAllowed',
      );
      final permissionStatus = await NativeSession.channel
          .invokeMapMethod<String, dynamic>('permissionStatus');
      next['sms'] = permissionStatus?['smsPermission'] == true;
      next['fineLocation'] = permissionStatus?['locationPermission'] == true;
      if (mounted) setState(() => status = next);
    });
  }

  Future<void> toggle(String key, bool value) async {
    ActionFeedback.tap();
    final label = key == 'purchaseScanning'
        ? 'Finance notification detection'
        : key == 'smsScanning'
        ? 'SMS transaction detection'
        : 'Location conditions';
    await guarded(
      context,
      () async {
        await ref.read(databaseProvider).pref(key, value);
        await AutomationSync.configure(
          await ref.read(databaseProvider).readAll(),
        );
        if (key == 'purchaseScanning' && value && mounted) {
          final access = await AutomationSync.status();
          if (!mounted) return;
          if (access['notifications'] != true) {
            await PermissionHints.request<void>(
              context,
              'notificationPermission',
            );
            if (!mounted) return;
          }
          await refresh();
        }
        if (key == 'smsScanning' && value && mounted) {
          await PermissionHints.request<bool>(context, 'smsPermission');
          if (!mounted) return;
          await AutomationSync.scanSms();
          await refresh();
        }
      },
      success: '$label ${value ? 'enabled' : 'disabled'}',
      successIcon: value ? DataAction.enabled.icon : DataAction.disabled.icon,
    );
  }

  Future<void> currentPlace() async {
    setState(() => busy = true);
    await guarded(context, () async {
      final allowed = await PermissionHints.request<bool>(
        context,
        'locationPermission',
      );
      if (allowed == null) return;
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
        placed = true;
      });
      await refresh();
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> saveRule(AppData data, {bool run = false}) async {
    if (busy) return;
    setState(() => busy = true);
    await guarded(context, () async {
      final latitude = double.tryParse(lat.text.trim()),
          longitude = double.tryParse(lng.text.trim());
      final program = sourceMode ? RuleCompiler.compile(code.text) : null;
      final hasSchedules = (program?['schedules'] as List? ?? []).isNotEmpty;
      bool preciseReminders = true;
      if (run && program?['needsNotifications'] == true) {
        final allowed = await PermissionHints.request<bool>(
          context,
          'reminderPermission',
        );
        if (allowed == null) return;
        if (!allowed) {
          throw StateError(
            'Enable FrekiHub notifications before running reminders.',
          );
        }
        final reminderState = await NativeSession.channel
            .invokeMapMethod<String, dynamic>('reminderStatus');
        preciseReminders = reminderState?['exact'] == true;
      }
      final needsLocation = program == null || program['needsLocation'] == true;
      if (name.text.trim().isEmpty) {
        throw StateError(
          sourceMode ? 'Enter a name for this rule.' : 'Name this place first.',
        );
      }
      if (needsLocation &&
          (!placed ||
              latitude == null ||
              longitude == null ||
              !latitude.isFinite ||
              !longitude.isFinite ||
              latitude.abs() > 90 ||
              longitude.abs() > 180)) {
        throw StateError(
          'Enter valid coordinates, then tap or drop the place into the IF block.',
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
        'lat': needsLocation ? (latitude ?? 0) : 0,
        'lng': needsLocation ? (longitude ?? 0) : 0,
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
            _resetDraft(keepSourceMode: false);
          }
        });
        toast(
          context,
          run
              ? (hasSchedules && !preciseReminders
                    ? 'Rule running · reminders may be delayed; use the clock icon for precise timing'
                    : 'Rule running')
              : sourceMode
              ? 'Rule saved · paused'
              : 'Condition saved',
          icon: run ? DataAction.started.icon : DataAction.saved.icon,
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
        toast(context, 'Rule stopped', icon: LucideIcons.square);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _toggleSavedRule(AppData data, Map<String, dynamic> rule) async {
    if (busy) return;
    final nextEnabled = rule['enabled'] != true;
    final isStructured = rule['source'] is String;
    setState(() => busy = true);
    await guarded(context, () async {
      Map<String, dynamic>? program;
      if (isStructured) {
        program = RuleCompiler.compile(rule['source'] as String);
      }
      if (nextEnabled && program?['needsNotifications'] == true) {
        final allowed = await PermissionHints.request<bool>(
          context,
          'reminderPermission',
        );
        if (allowed == null) return;
        if (!allowed) {
          throw StateError(
            'Enable FrekiHub notifications before running reminders.',
          );
        }
      }
      final needsLocation = program == null || program['needsLocation'] == true;
      if (nextEnabled &&
          needsLocation &&
          (await AutomationSync.status())['background'] != true) {
        throw StateError(
          'Allow precise location and location all the time before running this rule.',
        );
      }
      final config = AutomationSync.config(data);
      for (final raw in config['rules'] as List? ?? []) {
        if (raw['id'] == rule['id']) {
          raw['enabled'] = nextEnabled;
          if (program != null) raw['program'] = program;
        }
      }
      if (nextEnabled && needsLocation) {
        await ref.read(databaseProvider).pref('locationEnabled', true);
      }
      await ref.read(databaseProvider).pref('automation', jsonEncode(config));
      await AutomationSync.configure(
        await ref.read(databaseProvider).readAll(),
      );
      if (mounted) {
        setState(() {
          if (editing == rule['id'] && sourceMode) {
            ruleRunning = nextEnabled;
          }
        });
        toast(
          context,
          nextEnabled
              ? (isStructured ? 'Rule running' : 'Condition enabled')
              : (isStructured ? 'Rule stopped' : 'Condition paused'),
          icon: nextEnabled ? DataAction.started.icon : LucideIcons.pause,
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  String _describeSavedRule(Map<String, dynamic> rule) {
    final active = rule['enabled'] == true;
    if (rule['source'] is String) {
      final program = rule['program'] is Map
          ? Map<String, dynamic>.from(rule['program'] as Map)
          : null;
      final targets = (program?['targets'] as List? ?? const [])
          .map((t) => (t as Map)['target']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final scheduleCount = (program?['schedules'] as List? ?? const []).length;
      final details = <String>[
        active ? 'Running' : 'Paused',
        if (targets.isNotEmpty)
          targets.take(2).join(', ') +
              (targets.length > 2 ? ' +${targets.length - 2}' : '')
        else
          'structured rule',
        if (scheduleCount > 0)
          '$scheduleCount ${scheduleCount == 1 ? 'schedule' : 'schedules'}',
        if (program?['needsLocation'] == true)
          '${(rule['radius'] as num? ?? 150).round()} m',
      ];
      return details.join(' · ');
    }
    final rad = (rule['radius'] as num? ?? 150).round();
    final sessionKind = (rule['kind'] as String?) ?? 'OJT';
    final elseText = rule['else'] == 'clock_out' ? 'clock out' : 'continue';
    return '${active ? 'Active' : 'Paused'} · Within $rad m → $sessionKind · Else → $elseText';
  }

  Future<void> apps(AppData data) async {
    List<Map<String, dynamic>> installed = [];
    await guarded(context, () async {
      installed =
          (await NativeSession.channel.invokeListMethod('notificationApps') ??
                  [])
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList();
    });
    if (!mounted) return;
    final config = AutomationSync.config(data);
    final selected = Set<String>.from(config['apps'] as List? ?? []);
    installed.sort((a, b) {
      final aSel = selected.contains(a['package']);
      final bSel = selected.contains(b['package']);
      if (aSel != bSel) return aSel ? -1 : 1;
      final aName = ((a['name'] as String?) ?? '').toLowerCase();
      final bName = ((b['name'] as String?) ?? '').toLowerCase();
      return aName.compareTo(bName);
    });
    var query = '';
    await panel(
      context,
      StatefulBuilder(
        builder: (c, change) {
          final q = query.trim().toLowerCase();
          final filtered = installed.where((app) {
            if (q.isEmpty) return true;
            final label = ((app['name'] as String?) ?? '').toLowerCase();
            final pkg = ((app['package'] as String?) ?? '').toLowerCase();
            return label.contains(q) || pkg.contains(q);
          }).toList();
          return PanelContent(
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PanelHeading(
                  title: 'Scan selected finance apps',
                  trailing: IconButton(
                    tooltip: 'Close selection',
                    onPressed: withFeedback(() => Navigator.pop(c)),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
                ),
                if (installed.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: TextField(
                      onChanged: (v) => change(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search installed apps…',
                        prefixIcon: Icon(LucideIcons.search, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
            footer: AppButton(
              label: selected.isEmpty
                  ? 'Save selected apps'
                  : 'Save selected apps (${selected.length})',
              onPressed: () async {
                await guarded(c, () async {
                  config['apps'] = selected.toList();
                  await ref
                      .read(databaseProvider)
                      .pref('automation', jsonEncode(config));
                  await AutomationSync.configure(
                    await ref.read(databaseProvider).readAll(),
                  );
                  if (c.mounted) {
                    dataToast(c, 'Finance app selection', DataAction.saved);
                    Navigator.pop(c);
                  }
                });
              },
            ),
            scrollable: true,
            child: filtered.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        'No matching apps',
                        'Install a finance or messaging app, or try a different search.',
                        LucideIcons.smartphone,
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (c, index) {
                      final app = filtered[index];
                      final pkg = (app['package'] as String?) ?? '';
                      final label =
                          ((app['name'] as String?)?.trim().isNotEmpty ?? false)
                          ? app['name'] as String
                          : pkg;
                      return CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        title: Text(label),
                        subtitle: Text(pkg),
                        value: selected.contains(pkg),
                        onChanged: (v) => change(() {
                          v! ? selected.add(pkg) : selected.remove(pkg);
                        }),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final data = ref.watch(dataProvider).value;
    if (data != null &&
        widget.conditionName != null &&
        !_appliedInitialCondition) {
      _appliedInitialCondition = true;
      _selectConditionByName(data, widget.conditionName!);
    }
    final activeRulesCount = data == null
        ? 0
        : (AutomationSync.config(data)['rules'] as List? ?? const [])
              .where((r) => (r as Map)['enabled'] == true)
              .length;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final okColor = dark ? const Color(0xFF55C486) : const Color(0xFF1E8E5A);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: CanvasBackground()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      GlassCircleButton(
                        tooltip: 'Back',
                        icon: LucideIcons.arrowLeft,
                        onPressed: withFeedback(() => Navigator.pop(c))!,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Syntax builder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.titleLarge,
                            ),
                            Text(
                              'Conditions & automation',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (activeRulesCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: okColor.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: okColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$activeRulesCount active',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: okColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: data == null
                          ? const SkeletonList()
                          : builder(c, data),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget builder(BuildContext c, AppData data) {
    final colors = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final okColor = dark ? const Color(0xFF55C486) : const Color(0xFF1E8E5A);
    final config = AutomationSync.config(data);
    final rules = (config['rules'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final selectedAppsCount = (config['apps'] as List? ?? const []).length;
    final latVal = double.tryParse(lat.text.trim());
    final lngVal = double.tryParse(lng.text.trim());
    final coordsValid =
        latVal != null &&
        lngVal != null &&
        latVal.isFinite &&
        lngVal.isFinite &&
        latVal.abs() <= 90 &&
        lngVal.abs() <= 180;

    Widget block(String label, Widget content, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );

    return KeyboardFocusRevealer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // 1. Saved rules & conditions list
          if (rules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Saved automations (${rules.length})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (editing != null)
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : withFeedback(
                                    () => setState(() => _resetDraft()),
                                  ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(40, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                            icon: const Icon(LucideIcons.plus, size: 15),
                            label: const Text(
                              'New',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < rules.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Builder(
                        builder: (c) {
                          final rule = rules[i];
                          final isSelected = editing == rule['id'];
                          final isEnabled = rule['enabled'] == true;
                          return AnimatedContainer(
                            duration: Motion.duration(c, 160),
                            curve: Motion.curve,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primary.withValues(alpha: .07)
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? colors.primary.withValues(alpha: .45)
                                    : colors.outlineVariant.withValues(
                                        alpha: .35,
                                      ),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: withFeedback(
                                  () => setState(() => _applyRuleToDraft(rule)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    6,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 9,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isEnabled
                                              ? okColor
                                              : colors.outlineVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  rule['name'] as String,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (isSelected)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 1.5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: colors
                                                          .primaryContainer,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            99,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'Editing',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: colors
                                                            .onPrimaryContainer,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _describeSavedRule(rule),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: isEnabled
                                            ? 'Pause condition'
                                            : 'Enable condition',
                                        icon: Icon(
                                          isEnabled
                                              ? LucideIcons.pause
                                              : LucideIcons.play,
                                          size: 16,
                                        ),
                                        onPressed: busy
                                            ? null
                                            : withFeedback(
                                                () => _toggleSavedRule(
                                                  data,
                                                  rule,
                                                ),
                                              ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete condition',
                                        icon: const Icon(
                                          LucideIcons.trash2,
                                          size: 17,
                                        ),
                                        onPressed: busy
                                            ? null
                                            : withFeedback(() async {
                                                if (!await confirm(
                                                      c,
                                                      'Delete condition?',
                                                      'Existing sessions stay recorded.',
                                                    ) ||
                                                    !c.mounted) {
                                                  return;
                                                }
                                                final deletedId = rule['id'];
                                                await guarded(
                                                  c,
                                                  () async {
                                                    rules.removeWhere(
                                                      (r) =>
                                                          r['id'] == deletedId,
                                                    );
                                                    config['rules'] = rules;
                                                    await ref
                                                        .read(databaseProvider)
                                                        .pref(
                                                          'automation',
                                                          jsonEncode(config),
                                                        );
                                                    await AutomationSync.configure(
                                                      await ref
                                                          .read(
                                                            databaseProvider,
                                                          )
                                                          .readAll(),
                                                    );
                                                    if (mounted &&
                                                        editing == deletedId) {
                                                      setState(
                                                        () => _resetDraft(),
                                                      );
                                                    }
                                                  },
                                                  success: 'Condition deleted',
                                                  successIcon:
                                                      DataAction.deleted.icon,
                                                );
                                              }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 2. Builder mode switch card
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  sourceMode ? LucideIcons.code : LucideIcons.mapPin,
                  size: 20,
                ),
                title: const Text('Structured syntax'),
                subtitle: Text(
                  ruleRunning && sourceMode
                      ? 'Stop the running rule first to switch modes'
                      : 'Targets, conditions, schedules, actions and hints',
                ),
                value: sourceMode,
                onChanged: ruleRunning && sourceMode
                    ? null
                    : (v) => setState(() {
                        ActionFeedback.tap();
                        sourceMode = v;
                        if (!v) {
                          ruleRunning = false;
                        } else if (code.text.trim().isEmpty) {
                          code.text = RuleCompiler.visual(
                            kind: kind,
                            exit: exit,
                          );
                        }
                        lastCodeNeedsPlace = RuleCompiler.usesLocation(
                          code.text,
                        );
                      }),
              ),
            ),
          ),

          // 3. Rule name & place coordinates card
          block(
            sourceMode
                ? (editing == null ? 'Rule name' : 'Edit rule')
                : (editing == null ? 'Choose a place' : 'Edit condition'),
            trailing: editing != null
                ? TextButton.icon(
                    onPressed: busy
                        ? null
                        : withFeedback(() => setState(() => _resetDraft())),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(40, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 15),
                    label: Text(
                      sourceMode ? 'New condition' : 'New condition',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  )
                : null,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  readOnly: sourceMode && ruleRunning,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: sourceMode
                        ? 'Rule name'
                        : 'Place name · office, school, shop',
                    suffixIcon: name.text.isEmpty || (sourceMode && ruleRunning)
                        ? null
                        : IconButton(
                            tooltip: 'Clear name',
                            onPressed: withFeedback(
                              () => setState(() => name.clear()),
                            ),
                            icon: const Icon(LucideIcons.x, size: 16),
                          ),
                  ),
                ),
                if (requiresPlace) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lat,
                          readOnly: sourceMode && ruleRunning,
                          onChanged: (_) => setState(() {}),
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
                          readOnly: sourceMode && ruleRunning,
                          onChanged: (_) => setState(() {}),
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: withFeedback(
                          busy || (sourceMode && ruleRunning)
                              ? null
                              : currentPlace,
                        ),
                        icon: const Icon(LucideIcons.locateFixed, size: 17),
                        label: SkeletonValue(
                          loading: busy,
                          semanticsLabel: 'Finding location',
                          child: const Text('Use current location'),
                        ),
                      ),
                      LongPressDraggable<bool>(
                        data: true,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(14),
                          color: colors.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.mapPin,
                                  size: 16,
                                  color: colors.onPrimaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  name.text.trim().isEmpty
                                      ? 'Selected place'
                                      : name.text.trim(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: OutlinedButton.icon(
                          onPressed: sourceMode && ruleRunning
                              ? null
                              : withFeedback(
                                  () => setState(() => placed = true),
                                ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          icon: Icon(
                            placed
                                ? LucideIcons.circleCheck
                                : LucideIcons.gripVertical,
                            size: 16,
                            color: placed ? okColor : null,
                          ),
                          label: Text(
                            placed
                                ? 'Placed in IF'
                                : (name.text.trim().isEmpty
                                      ? 'Tap or drag into IF'
                                      : 'Place ${name.text.trim()} in IF'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // 4. IF · Location radius card (when location predicate is active)
          if (requiresPlace)
            block(
              'IF · Location is inside',
              trailing: Text(
                '${radius.round()} m',
                style: TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              DragTarget<bool>(
                onAcceptWithDetails: (_) => setState(() => placed = true),
                builder: (c, candidates, rejected) {
                  final hovering = candidates.isNotEmpty;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: sourceMode && ruleRunning
                            ? null
                            : withFeedback(() => setState(() => placed = true)),
                        child: AnimatedContainer(
                          duration: Motion.duration(c, 150),
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: placed
                                ? okColor.withValues(alpha: .1)
                                : hovering
                                ? colors.primaryContainer
                                : colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: placed
                                  ? okColor.withValues(alpha: .4)
                                  : hovering
                                  ? colors.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                placed
                                    ? LucideIcons.mapPinCheck
                                    : LucideIcons.mapPin,
                                size: 17,
                                color: placed
                                    ? okColor
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  placed
                                      ? 'Within ${radius.round()} m of ${name.text.trim().isEmpty ? 'selected place' : name.text.trim()}${coordsValid ? '' : ' · enter coordinates'}'
                                      : 'Tap or drop a location here',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: placed
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: radius,
                        min: 100,
                        max: 1000,
                        divisions: 18,
                        label: '${radius.round()} m',
                        onChanged: sourceMode && ruleRunning
                            ? null
                            : (v) => setState(() => radius = v),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final preset in const [100, 150, 250, 500, 1000])
                            ChoiceChip(
                              label: Text(
                                preset == 1000 ? '1 km' : '$preset m',
                                style: const TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 11,
                                ),
                              ),
                              selected: radius.round() == preset,
                              onSelected: sourceMode && ruleRunning
                                  ? null
                                  : (_) {
                                      ActionFeedback.tap();
                                      setState(
                                        () => radius = preset.toDouble(),
                                      );
                                    },
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

          // 5. Structured Code Editor OR Visual THEN/ELSE + Code preview
          if (sourceMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(16),
                child: RuleCodeEditor(
                  controller: code,
                  settingFields: data.prefs.keys
                      .map((k) => 'settings.$k')
                      .where(
                        (k) =>
                            k != 'settings.automation' &&
                            !k.startsWith('settings.purchaseNotice:') &&
                            !k.startsWith('settings.ruleToast:') &&
                            !k.startsWith('settings.deletedLog:'),
                      ),
                  create: busy
                      ? null
                      : () => setState(() => _resetDraft(keepSourceMode: true)),
                  running: ruleRunning,
                  busy: busy,
                  run: () => saveRule(data, run: true),
                  stop: () => stopRule(data),
                ),
              ),
            ),
          if (!sourceMode) ...[
            block(
              'THEN · Clock in',
              selectField('Session type', kind, [
                'OJT',
                'Work',
                'Study',
                'Personal',
              ], (v) => setState(() => kind = v)),
            ),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.code,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Generated rule preview',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: withFeedback(
                            () => setState(() {
                              code.text = RuleCompiler.visual(
                                kind: kind,
                                exit: exit,
                              );
                              sourceMode = true;
                              ruleRunning = false;
                              lastCodeNeedsPlace = true;
                            }),
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(40, 32),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          child: const Text(
                            'Edit in syntax',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        RuleCompiler.visual(kind: kind, exit: exit),
                        style: TextStyle(
                          fontFamily: 'Geist Mono',
                          fontSize: 11.5,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          FilledButton(
            onPressed: withFeedback(
              busy || (sourceMode && ruleRunning) ? null : () => saveRule(data),
            ),
            child: SkeletonValue(
              loading: busy,
              child: Text(
                editing == null ? 'Save condition' : 'Update condition',
              ),
            ),
          ),
          if (sourceMode)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                ruleRunning
                    ? 'Stop the rule above to edit or save changes as paused.'
                    : 'Save keeps a structured rule paused · tap Play in the editor to save and run.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),

          const SizedBox(height: 18),

          // 6. Location background permissions & diagnostics surface
          Surface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                if (status['logging_paused'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Location history is paused while ${status['pending_count']} pending actions sync. Saved records and location rules are retained.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                if (status['background'] != true) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: withFeedback(() async {
                          await guarded(context, () async {
                            await PermissionHints.request<bool>(
                              context,
                              'locationPermission',
                            );
                          });
                          await refresh();
                        }),
                        child: const Text('Allow precise location'),
                      ),
                      OutlinedButton(
                        onPressed: withFeedback(() async {
                          await guarded(context, () async {
                            await PermissionHints.request<void>(
                              context,
                              'backgroundPermission',
                            );
                          });
                          await refresh();
                        }),
                        child: const Text('Allow location all the time'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  'Android may delay background checks. Location rules require precise location and “Allow all the time”. Other rules work without GPS.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 7. Finance transaction detection surface
          Surface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Detect Finance transactions'),
                  subtitle: const Text(
                    'Recognized expense and income alerts become editable Finance entries',
                  ),
                  value: data.prefs['purchaseScanning'] == 'true',
                  onChanged: (v) => toggle('purchaseScanning', v),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: withFeedback(() => apps(data)),
                      icon: const Icon(LucideIcons.smartphone, size: 16),
                      label: Text(
                        selectedAppsCount > 0
                            ? 'Choose finance apps ($selectedAppsCount)'
                            : 'Choose finance apps',
                      ),
                    ),
                    if (status['notifications'] != true)
                      OutlinedButton(
                        onPressed: withFeedback(() async {
                          await guarded(context, () async {
                            await PermissionHints.request<void>(
                              context,
                              'notificationPermission',
                            );
                          });
                          await refresh();
                        }),
                        child: const Text('Allow notification access'),
                      ),
                  ],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Detect Finance transactions from SMS'),
                  subtitle: const Text(
                    'Recognized transaction SMS become editable Finance entries',
                  ),
                  value: data.prefs['smsScanning'] == 'true',
                  onChanged: (v) => toggle('smsScanning', v),
                ),
                if (status['sms'] != true ||
                    (data.prefs['purchaseScanning'] == 'true' &&
                        status['receipts'] != true)) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status['sms'] != true)
                        OutlinedButton(
                          onPressed: withFeedback(() async {
                            await guarded(context, () async {
                              await PermissionHints.request<bool>(
                                context,
                                'smsPermission',
                              );
                            });
                            await refresh();
                          }),
                          child: const Text('Allow SMS access'),
                        ),
                      if (data.prefs['purchaseScanning'] == 'true' &&
                          status['receipts'] != true)
                        OutlinedButton(
                          onPressed: withFeedback(() async {
                            await guarded(context, () async {
                              await PermissionHints.request<bool>(
                                context,
                                'receiptNotificationPermission',
                              );
                            });
                            await refresh();
                          }),
                          child: const Text(
                            'Allow saved-transaction notifications',
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Only selected apps are scanned. OTPs and unrelated alerts are skipped. '
                  'Clear transaction amounts and available sender or merchant labels '
                  'are used; unclear messages are skipped.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const KeyboardScrollSpacer(baseBottom: 24),
        ],
      ),
    );
  }
}
