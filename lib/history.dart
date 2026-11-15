part of 'screens.dart';

enum _HistoryMenuAction { filters, formats, toggleView, toggleSelection }

class HistoryScreen extends ConsumerStatefulWidget {
  final AppData data;
  const HistoryScreen({super.key, required this.data});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final search = TextEditingController();
  final selected = <String>{};
  int sortColumn = 0;
  bool ascending = false, selection = false, tableView = false;
  final recordScroll = ScrollController();
  String month = 'All months',
      kind = 'All types',
      weekday = 'All weekdays',
      notes = 'All notes';
  late List<double> widths;
  static const defaults = [150.0, 96.0, 110.0, 110.0, 120.0, 240.0];
  static const headers = [
    'Date',
    'Type',
    'Clock in',
    'Clock out',
    'Duration',
    'Notes',
  ];

  @override
  void initState() {
    super.initState();
    try {
      widths = (jsonDecode(widget.data.prefs['columnWidths']!) as List)
          .map((v) => (v as num).toDouble())
          .toList();
      if (widths.length != 6 ||
          widths.any((v) => !v.isFinite || v < 64 || v > 2000)) {
        widths = [...defaults];
      }
    } catch (_) {
      widths = [...defaults];
    }
  }

  @override
  void dispose() {
    search.dispose();
    recordScroll.dispose();
    super.dispose();
  }

  List<Session> get rows {
    final q = search.text.trim().toLowerCase();
    final list = widget.data.sessions
        .where(
          (s) =>
              (month == 'All months' || s.day.startsWith(month)) &&
              (kind == 'All types' || s.kind == kind) &&
              (weekday == 'All weekdays' ||
                  DateFormat('EEEE').format(calendarDate(s.day)) == weekday) &&
              (notes == 'All notes' ||
                  (notes == 'With notes'
                      ? s.note.isNotEmpty
                      : s.note.isEmpty)) &&
              (q.isEmpty ||
                  '${s.day} ${s.kind} ${s.note} ${sessionDate(widget.data, s)}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
    Object value(Session s) => switch (sortColumn) {
      0 => s.day,
      1 => s.kind,
      2 => s.started,
      3 => s.ended ?? 9223372036854775807,
      4 => durationOf(s),
      _ => s.note,
    };
    list.sort((a, b) {
      final av = value(a), bv = value(b);
      var comparison = av is int
          ? av.compareTo(bv as int)
          : (av as String).compareTo(bv as String);
      if (comparison == 0) comparison = a.started.compareTo(b.started);
      if (comparison == 0) comparison = a.id.compareTo(b.id);
      return ascending ? comparison : -comparison;
    });
    return list;
  }

  Future<void> formats() => panel(
    context,
    StatefulBuilder(
      builder: (c, setLocal) {
        final theme = Theme.of(c);
        final colors = theme.colorScheme;
        final clockFormat = widget.data.prefs['clockFormat'] ?? '24';
        final dateFormat = widget.data.prefs['dateFormat'] ?? 'EEE, d MMM';
        final now = DateTime.now();
        return PanelContent(
          header: PanelHeading(
            title: 'Date & time',
            trailing: IconButton(
              tooltip: 'Close',
              onPressed: withFeedback(() => Navigator.pop(c)),
              icon: const Icon(LucideIcons.x, size: 18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CLOCK FORMAT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    for (final f in ['12', '24'])
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: withFeedback(() async {
                            ActionFeedback.tap();
                            await guarded(c, () async {
                              await ref
                                  .read(databaseProvider)
                                  .pref('clockFormat', f);
                              if (c.mounted) {
                                dataToast(
                                  c,
                                  'Clock format',
                                  DataAction.updated,
                                );
                                Navigator.pop(c);
                              }
                            });
                          }),
                          child: AnimatedContainer(
                            duration: Motion.duration(c, 160),
                            curve: Motion.curve,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: clockFormat == f
                                  ? colors.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: clockFormat == f
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .06,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              '$f-hour · ${DateFormat(f == '12' ? 'h:mm a' : 'HH:mm').format(now)}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: clockFormat == f
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: clockFormat == f
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'DATE FORMAT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final f in [
                'EEE, d MMM',
                'dd/MM/yyyy',
                'MM/dd/yyyy',
                'd MMM yyyy',
                'yyyy-MM-dd',
                'relative',
              ]) ...[
                Material(
                  color: dateFormat == f
                      ? colors.primaryContainer
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    title: Text(
                      f == 'relative'
                          ? 'Relative · 2 days ago'
                          : DateFormat(f).format(now),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: dateFormat == f
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: dateFormat == f
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      f,
                      style: TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 11,
                        color: dateFormat == f
                            ? colors.onPrimaryContainer.withValues(alpha: .75)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    trailing: dateFormat == f
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: colors.onPrimaryContainer,
                          )
                        : null,
                    onTap: withFeedback(() async {
                      await guarded(c, () async {
                        await ref.read(databaseProvider).pref('dateFormat', f);
                        if (c.mounted) {
                          dataToast(c, 'Date format', DataAction.updated);
                          Navigator.pop(c);
                        }
                      });
                    }),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    ),
  );

  Future<void> openFiltersSheet(
    List<String> months,
    List<String> types,
  ) => panel(
    context,
    StatefulBuilder(
      builder: (sheetContext, setSheet) {
        final colors = Theme.of(sheetContext).colorScheme;
        final clockFormat = widget.data.prefs['clockFormat'] ?? '24';
        final dateFormat = widget.data.prefs['dateFormat'] ?? 'EEE, d MMM';
        final filteredCount = rows.length;
        return PanelContent(
          header: PanelHeading(
            title: 'Filters',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasActiveQuery)
                  TextButton(
                    onPressed: withFeedback(() {
                      resetFilters();
                      setSheet(() {});
                    }),
                    child: const Text('Reset'),
                  ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: withFeedback(() => Navigator.pop(sheetContext)),
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ],
            ),
          ),
          footer: PanelActions(
            children: [
              AppButton(
                label:
                    'Show $filteredCount ${filteredCount == 1 ? 'session' : 'sessions'}',
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              selectField('Month', month, ['All months', ...months], (v) {
                setState(() => month = v);
                setSheet(() {});
              }),
              const SizedBox(height: 10),
              selectField('Type', kind, ['All types', ...types], (v) {
                setState(() => kind = v);
                setSheet(() {});
              }),
              const SizedBox(height: 10),
              selectField(
                'Weekday',
                weekday,
                [
                  'All weekdays',
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                  'Sunday',
                ],
                (v) {
                  setState(() => weekday = v);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 10),
              selectField(
                'Notes',
                notes,
                ['All notes', 'With notes', 'Without notes'],
                (v) {
                  setState(() => notes = v);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: .45),
              ),
              const SizedBox(height: 14),
              Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Icon(
                    LucideIcons.calendarDays,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  title: const Text(
                    'Date & time format',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '$clockFormat-hour · $dateFormat',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  onTap: withFeedback(() {
                    Navigator.pop(sheetContext);
                    formats();
                  }),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  int get activeFilters => [
    month != 'All months',
    kind != 'All types',
    weekday != 'All weekdays',
    notes != 'All notes',
  ].where((v) => v).length;

  bool get hasActiveQuery => activeFilters > 0 || search.text.trim().isNotEmpty;

  void resetFilters() => setState(() {
    month = 'All months';
    kind = 'All types';
    weekday = 'All weekdays';
    notes = 'All notes';
    search.clear();
  });

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    selected.removeWhere((id) => !widget.data.sessions.any((s) => s.id == id));
    if (month != 'All months' &&
        !widget.data.sessions.any((s) => s.day.startsWith(month))) {
      month = 'All months';
    }
  }

  Future<void> bulkDelete() async {
    if (!await confirm(
      context,
      'Delete ${selected.length} sessions?',
      'The selected records and notes will be permanently removed.',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    await guarded(
      context,
      () async {
        final db = ref.read(databaseProvider);
        await (db.delete(db.sessions)..where((s) => s.id.isIn(selected))).go();
        setState(() {
          selected.clear();
          selection = false;
        });
      },
      success: 'Selected sessions deleted',
      successIcon: DataAction.deleted.icon,
    );
  }

  void _toggleSelected(String id) {
    setState(() {
      if (selected.contains(id)) {
        selected.remove(id);
      } else {
        selected.add(id);
      }
    });
  }

  void _enterSelection(String id) {
    ActionFeedback.tap();
    setState(() {
      selection = true;
      selected.clear();
      selected.add(id);
    });
  }

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final months = {
      ...widget.data.sessions.map((s) => s.day.substring(0, 7)),
    }.toList()..sort();
    final types = {
      ...widget.data.sessions.map((s) => s.kind),
      'OJT',
      'Work',
      'Study',
      'Personal',
    }.toList();
    final list = rows;
    final hasRules =
        (AutomationSync.config(widget.data)['rules'] as List? ?? []).isNotEmpty;

    final totalSeconds = list.fold<int>(0, (sum, s) => sum + durationOf(s));
    final uniqueDays = {for (final s in list) s.day}.length;
    final hasLive = list.any((s) => s.ended == null);
    final byKind = <String, int>{};
    for (final s in list) {
      final sec = durationOf(s);
      if (sec > 0) {
        byKind.update(s.kind, (v) => v + sec, ifAbsent: () => sec);
      }
    }
    final breakdown = byKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hairline = colors.outlineVariant.withValues(alpha: dark ? .35 : .55);
    final bottomSafe = math.max(
      MediaQuery.paddingOf(c).bottom,
      MediaQuery.viewPaddingOf(c).bottom,
    );

    return WidthLayoutBuilder(
      builder: (c, width) {
        final narrow = width < 600;
        final showList = narrow && !tableView;
        final inset = width < 380 ? 16.0 : 24.0;
        final horizontal = math.max(inset, (width - 720) / 2);

        return Scrollbar(
          controller: recordScroll,
          child: KeyboardFocusRevealer(
            child: CustomScrollView(
              key: const PageStorageKey('SESSIONS'),
              controller: recordScroll,
              slivers: [
                // 1. Compact Header (~110px)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 44,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 56),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'TIME & FOCUS LEDGER',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: PageTitle('SESSIONS'),
                              ),
                            ),
                            if (hasRules)
                              Tooltip(
                                message: 'Automation rules saved · Review in Syntax builder',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: withFeedback(
                                    () => openSyntaxBuilder(c),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.workflow,
                                          size: 14,
                                          color: colors.primary,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Rules',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // 2. Inline Summary (~120px, no card container)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: SliverToBoxAdapter(
                    child: _InlineSessionSummary(
                      filtered: hasActiveQuery,
                      count: list.length,
                      days: uniqueDays,
                      totalSeconds: totalSeconds,
                      hasLive: hasLive,
                      breakdown: breakdown,
                      hairline: hairline,
                    ),
                  ),
                ),

                // 3. Search Bar (~52px, integrated filter access)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 6),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search sessions...',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant.withValues(alpha: .75),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        prefixIcon: Icon(
                          LucideIcons.search,
                          size: 17,
                          color: colors.onSurfaceVariant,
                        ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (search.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear search',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(36, 40),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: withFeedback(() {
                                  search.clear();
                                  setState(() {});
                                }),
                                icon: const Icon(LucideIcons.x, size: 16),
                              ),
                            IconButton(
                              tooltip: activeFilters == 0
                                  ? 'Filters'
                                  : 'Filters · $activeFilters active',
                              style: IconButton.styleFrom(
                                minimumSize: const Size(40, 40),
                                padding: const EdgeInsets.only(right: 4),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: withFeedback(
                                () => openFiltersSheet(months, types),
                              ),
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    LucideIcons.slidersHorizontal,
                                    size: 17,
                                    color: activeFilters > 0
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                  if (activeFilters > 0)
                                    Positioned(
                                      right: -4,
                                      top: -4,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: colors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: hairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: colors.primary.withValues(alpha: .55),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Compact Toolbar (~38-42px) + Contextual Selection Bar
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 38),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        hasActiveQuery
                                            ? '${list.length} OF ${widget.data.sessions.length} RECORDS'
                                            : '${list.length} ${list.length == 1 ? 'RECORD' : 'RECORDS'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Geist Mono',
                                          fontSize: 11,
                                          letterSpacing: 0.8,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (hasActiveQuery) ...[
                                      const SizedBox(width: 8),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: withFeedback(resetFilters),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            'Reset',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (anchor) => Semantics(
                                  button: true,
                                  label: 'Sort by ${headers[sortColumn]}',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: withFeedback(() async {
                                      final value = await showChoiceMenu<int>(
                                        anchor,
                                        choices: {
                                          for (
                                            var i = 0;
                                            i < headers.length;
                                            i++
                                          )
                                            i: headers[i],
                                        },
                                        selected: sortColumn,
                                      );
                                      if (value != null && mounted) {
                                        setState(() => sortColumn = value);
                                      }
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            headers[sortColumn],
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: colors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Icon(
                                            LucideIcons.chevronDown,
                                            size: 13,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: ascending
                                    ? 'Ascending; switch to descending'
                                    : 'Descending; switch to ascending',
                                child: Semantics(
                                  button: true,
                                  label: ascending
                                      ? 'Ascending; switch to descending'
                                      : 'Descending; switch to ascending',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: withFeedback(
                                      () => setState(
                                        () => ascending = !ascending,
                                      ),
                                    ),
                                    child: SizedBox(
                                      width: 34,
                                      height: 36,
                                      child: Icon(
                                        ascending
                                            ? LucideIcons.arrowUp
                                            : LucideIcons.arrowDown,
                                        size: 15,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (anchor) => Tooltip(
                                  message: 'View and selection options',
                                  child: Semantics(
                                    button: true,
                                    label: 'View and selection options',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: withFeedback(() async {
                                        final choices =
                                            <_HistoryMenuAction?, String>{
                                              _HistoryMenuAction.filters:
                                                  activeFilters == 0
                                                  ? 'Filters'
                                                  : 'Filters · $activeFilters',
                                              _HistoryMenuAction.formats:
                                                  'Date & time',
                                              if (narrow)
                                                _HistoryMenuAction.toggleView:
                                                    tableView
                                                    ? 'List view'
                                                    : 'Table view',
                                              if (list.isNotEmpty || selection)
                                                _HistoryMenuAction
                                                    .toggleSelection: selection
                                                    ? 'Done selecting'
                                                    : 'Select sessions',
                                            };
                                        final action =
                                            await showChoiceMenu<
                                              _HistoryMenuAction?
                                            >(
                                              anchor,
                                              choices: choices,
                                              selected: null,
                                            );
                                        if (!mounted || action == null) return;
                                        switch (action) {
                                          case _HistoryMenuAction.filters:
                                            await openFiltersSheet(
                                              months,
                                              types,
                                            );
                                          case _HistoryMenuAction.formats:
                                            await formats();
                                          case _HistoryMenuAction.toggleView:
                                            ActionFeedback.tap();
                                            setState(
                                              () => tableView = !tableView,
                                            );
                                          case _HistoryMenuAction
                                              .toggleSelection:
                                            setState(() {
                                              selection = !selection;
                                              selected.clear();
                                            });
                                        }
                                      }),
                                      child: SizedBox(
                                        width: 34,
                                        height: 36,
                                        child: Icon(
                                          LucideIcons.ellipsis,
                                          size: 16,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizeTransitionPanel(
                          alignment: Alignment.topCenter,
                          child: selection
                              ? Container(
                                  margin: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: dark ? .12 : .06,
                                    ),
                                    border: Border(
                                      top: BorderSide(color: hairline),
                                      bottom: BorderSide(color: hairline),
                                    ),
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        selected.isEmpty
                                            ? 'Tap sessions to select'
                                            : '${selected.length} selected',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            onTap: list.isEmpty
                                                ? null
                                                : withFeedback(() {
                                                    setState(() {
                                                      if (selected.length ==
                                                          list.length) {
                                                        selected.clear();
                                                      } else {
                                                        selected.addAll(
                                                          list.map((s) => s.id),
                                                        );
                                                      }
                                                    });
                                                  }),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 4,
                                                  ),
                                              child: Text(
                                                selected.length ==
                                                            list.length &&
                                                        list.isNotEmpty
                                                    ? 'Clear selection'
                                                    : 'Select visible',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: colors.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (selected.isNotEmpty)
                                            Material(
                                              color: colors.error,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                                onTap: withFeedback(bulkDelete),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5,
                                                      ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        LucideIcons.trash2,
                                                        size: 13,
                                                        color: colors.onError,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        'Delete ${selected.length}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: colors.onError,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            onTap: withFeedback(() {
                                              setState(() {
                                                selection = false;
                                                selected.clear();
                                              });
                                            }),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 4,
                                                  ),
                                              child: Text(
                                                'Done',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: colors.onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),

                // 5. Continuous Flat Record List (or Table view)
                if (list.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      8,
                      horizontal,
                      108 + bottomSafe,
                    ),
                    sliver: const SliverToBoxAdapter(
                      child: EmptyState(
                        'No matching sessions.',
                        'Adjust the filters or record your first hours.',
                        LucideIcons.table2,
                      ),
                    ),
                  )
                else if (showList) ...[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    sliver: SliverToBoxAdapter(
                      child: Container(height: 1, color: hairline),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: 108 + bottomSafe),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((c, index) {
                        final s = list[index];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FlatSessionRow(
                              data: widget.data,
                              session: s,
                              horizontal: horizontal,
                              selecting: selection,
                              selected: selected.contains(s.id),
                              onTap: () {
                                if (selection) {
                                  _toggleSelected(s.id);
                                } else {
                                  panel(
                                    c,
                                    SessionForm(
                                      data: widget.data,
                                      session: s,
                                      day: s.day,
                                    ),
                                  );
                                }
                              },
                              onLongPress: selection
                                  ? null
                                  : () => _enterSelection(s.id),
                            ),
                            if (index < list.length - 1)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontal,
                                ),
                                child: Container(height: 1, color: hairline),
                              ),
                          ],
                        );
                      }, childCount: list.length),
                    ),
                  ),
                ] else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      8,
                      horizontal,
                      108 + bottomSafe,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSessionTable(c, list, colors, dark),
                          const SizedBox(height: 10),
                          Text(
                            'Scroll sideways for more columns. Drag a header divider to resize neighbouring columns; double tap it to reset.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: KeyboardScrollSpacer(baseBottom: 108 + bottomSafe),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionTable(
    BuildContext c,
    List<Session> list,
    ColorScheme colors,
    bool dark,
  ) {
    final totalWidth = widths.fold(0.0, (a, b) => a + b) + (selection ? 48 : 0);
    final maxTableHeight = math.max(240.0, MediaQuery.sizeOf(c).height * .52);
    return Surface(
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      child: SizedBox(
        height: math.min(maxTableHeight, list.length * 56.0 + 48.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .45),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (selection) const SizedBox(width: 48),
                      ...List.generate(
                        6,
                        (i) => SizedBox(
                          width: widths[i],
                          height: 48,
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: withFeedback(
                                    () => setState(() {
                                      if (sortColumn == i) {
                                        ascending = !ascending;
                                      } else {
                                        sortColumn = i;
                                        ascending = true;
                                      }
                                    }),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            headers[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: sortColumn == i
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              fontSize: 11.5,
                                              letterSpacing: .2,
                                              color: sortColumn == i
                                                  ? colors.onSurface
                                                  : colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        if (sortColumn == i)
                                          Icon(
                                            ascending
                                                ? LucideIcons.arrowUp
                                                : LucideIcons.arrowDown,
                                            size: 12,
                                            color: colors.onSurface,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (i < 5)
                                Semantics(
                                  label:
                                      'Resize ${headers[i]} column; double tap to reset',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onDoubleTap: () {
                                      setState(() => widths = [...defaults]);
                                      ref
                                          .read(databaseProvider)
                                          .pref(
                                            'columnWidths',
                                            jsonEncode(widths),
                                          );
                                    },
                                    onHorizontalDragUpdate: (delta) {
                                      setState(() {
                                        final shift = delta.delta.dx.clamp(
                                          64 - widths[i],
                                          widths[i + 1] - 64,
                                        );
                                        widths[i] += shift;
                                        widths[i + 1] -= shift;
                                      });
                                    },
                                    onHorizontalDragEnd: (_) => ref
                                        .read(databaseProvider)
                                        .pref(
                                          'columnWidths',
                                          jsonEncode(widths),
                                        ),
                                    child: SizedBox(
                                      width: 16,
                                      child: Center(
                                        child: Container(
                                          width: 3,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: colors.onSurface.withValues(
                                              alpha: .16,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    itemCount: list.length,
                    itemExtent: 56,
                    itemBuilder: (c, n) {
                      final s = list[n];
                      final isSelected = selected.contains(s.id);
                      final running = s.ended == null;
                      final accent = running
                          ? (dark
                                ? const Color(0xFF55C486)
                                : const Color(0xFF1E8E5A))
                          : sessionTypeColor(s.kind, dark);
                      final values = [
                        sessionDate(widget.data, s),
                        s.kind,
                        clockTime(widget.data, s.started),
                        running ? 'Running' : clockTime(widget.data, s.ended!),
                        elapsed(durationOf(s)),
                        s.note.isEmpty ? '—' : s.note,
                      ];
                      return InkWell(
                        onTap: withFeedback(() {
                          if (selection) {
                            _toggleSelected(s.id);
                          } else {
                            panel(
                              c,
                              SessionForm(
                                data: widget.data,
                                day: s.day,
                                session: s,
                              ),
                            );
                          }
                        }),
                        onLongPress: selection
                            ? null
                            : () => _enterSelection(s.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary.withValues(alpha: .08)
                                : n.isOdd
                                ? colors.onSurface.withValues(alpha: .02)
                                : null,
                            border: n < list.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: colors.outlineVariant.withValues(
                                        alpha: .35,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              if (selection)
                                SizedBox(
                                  width: 48,
                                  child: Checkbox(
                                    value: isSelected,
                                    onChanged: (v) {
                                      ActionFeedback.tap();
                                      _toggleSelected(s.id);
                                    },
                                  ),
                                ),
                              ...List.generate(6, (i) {
                                if (i == 1) {
                                  return SizedBox(
                                    width: widths[i],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: .12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: Text(
                                            values[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return SizedBox(
                                  width: widths[i],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      values[i],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: i == 5
                                            ? 'Geist'
                                            : 'Geist Mono',
                                        fontSize: 12,
                                        fontWeight: i == 4
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: (i == 3 && running)
                                            ? accent
                                            : (i == 5 && s.note.isEmpty)
                                            ? colors.onSurfaceVariant
                                                  .withValues(alpha: .5)
                                            : colors.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSessionSummary extends StatelessWidget {
  final bool filtered, hasLive;
  final int count, days, totalSeconds;
  final List<MapEntry<String, int>> breakdown;
  final Color hairline;
  const _InlineSessionSummary({
    required this.filtered,
    required this.count,
    required this.days,
    required this.totalSeconds,
    required this.hasLive,
    required this.breakdown,
    required this.hairline,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final avg = count == 0 ? 0 : totalSeconds ~/ count;
    final liveColor = dark ? const Color(0xFF6CE59E) : const Color(0xFF1E8E5A);
    return Semantics(
      container: true,
      label:
          '${filtered ? 'Filtered sessions' : 'All sessions'}: ${sessionDurationLabel(totalSeconds)}, $count sessions across $days days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sessionDurationLabel(totalSeconds),
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.2,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasLive) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: liveColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                          color: liveColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '$count ${count == 1 ? 'session' : 'sessions'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 3,
                child: Row(
                  children: [
                    for (var i = 0; i < breakdown.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: math.max(1, breakdown[i].value),
                        child: ColoredBox(
                          color: sessionTypeColor(breakdown[i].key, dark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in breakdown)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: sessionTypeColor(entry.key, dark),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${entry.key} ${sessionDurationLabel(entry.value)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(height: 1, color: hairline),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _InlineStat(
                      value: '$count',
                      label: count == 1 ? 'session' : 'sessions',
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _InlineStat(
                      value: count == 0 ? '0m' : sessionDurationLabel(avg),
                      label: 'average',
                      mono: true,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _InlineStat(
                      value: '$days',
                      label: days == 1 ? 'day' : 'days',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String value, label;
  final bool mono;
  const _InlineStat({
    required this.value,
    required this.label,
    this.mono = false,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontFamily: mono ? 'Geist Mono' : 'Geist',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

class _FlatSessionRow extends StatelessWidget {
  final AppData data;
  final Session session;
  final double horizontal;
  final bool selecting, selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FlatSessionRow({
    required this.data,
    required this.session,
    required this.horizontal,
    required this.selecting,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final running = session.ended == null;
    final accent = running
        ? (dark ? const Color(0xFF55C486) : const Color(0xFF1E8E5A))
        : sessionTypeColor(session.kind, dark);
    final conditionName = session.note.startsWith('Automatic · ')
        ? session.note.substring('Automatic · '.length)
        : null;

    return Semantics(
      selected: selecting ? selected : null,
      child: Material(
        color: selecting && selected
            ? colors.primary.withValues(alpha: dark ? .12 : .06)
            : Colors.transparent,
        child: InkWell(
          onTap: withFeedback(onTap),
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selecting) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 12),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? colors.primary : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              LucideIcons.check,
                              size: 13,
                              color: colors.onPrimary,
                            )
                          : null,
                    ),
                  ),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              sessionDate(data, session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.2,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            elapsed(durationOf(session)),
                            style: TextStyle(
                              fontFamily: 'Geist Mono',
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                              color: running ? accent : colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            session.kind,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          Text(
                            '·',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${clockTime(data, session.started)} – ${running ? 'Running' : clockTime(data, session.ended!)}',
                            style: TextStyle(
                              fontFamily: 'Geist Mono',
                              fontSize: 12.5,
                              color: running ? accent : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (session.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            session.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (conditionName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: withFeedback(
                              () => openSyntaxBuilder(
                                c,
                                conditionName: conditionName,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.workflow,
                                    size: 12,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Condition set',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
