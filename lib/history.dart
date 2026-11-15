part of 'screens.dart';

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
  bool ascending = false,
      selection = false,
      tableView = false,
      filtersExpanded = false;
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

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(c).width < 600;
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
    final showList = narrow && !tableView;

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
    final maxListHeight = math.max(240.0, MediaQuery.sizeOf(c).height * .52);

    return PageBody(
      title: 'SESSIONS',
      subtitle: 'Time & focus ledger',
      children: [
        _SessionSummaryCard(
          filtered: hasActiveQuery,
          count: list.length,
          days: uniqueDays,
          totalSeconds: totalSeconds,
          hasLive: hasLive,
          breakdown: breakdown,
        ),
        if (hasRules)
          Surface(
            padding: EdgeInsets.zero,
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.workflow,
                  size: 17,
                  color: colors.primary,
                ),
              ),
              title: const Text(
                'Automation rules saved',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Review rules and Run/Stop status in Syntax builder',
                style: TextStyle(fontSize: 12),
              ),
              trailing: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              onTap: withFeedback(() => openSyntaxBuilder(c)),
            ),
          ),
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search dates, types and notes',
            hintStyle: TextStyle(
              fontSize: 14,
              color: colors.onSurfaceVariant.withValues(alpha: .75),
            ),
            isDense: true,
            filled: true,
            fillColor: colors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            prefixIcon: Icon(
              LucideIcons.search,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: withFeedback(() {
                      search.clear();
                      setState(() {});
                    }),
                    icon: const Icon(LucideIcons.x, size: 17),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .4),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: colors.primary.withValues(alpha: .5),
                width: 1.5,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ToolbarPill(
              icon: filtersExpanded
                  ? LucideIcons.chevronUp
                  : LucideIcons.slidersHorizontal,
              label: activeFilters == 0
                  ? 'Filters'
                  : 'Filters · $activeFilters',
              active: filtersExpanded || activeFilters > 0,
              onTap: withFeedback(
                () => setState(() => filtersExpanded = !filtersExpanded),
              ),
            ),
            Builder(
              builder: (anchor) => _ToolbarPill(
                icon: LucideIcons.arrowUpDown,
                label: 'Sort · ${headers[sortColumn]}',
                trailingIcon: LucideIcons.chevronDown,
                onTap: withFeedback(() async {
                  final value = await showChoiceMenu<int>(
                    anchor,
                    choices: {
                      for (var i = 0; i < headers.length; i++) i: headers[i],
                    },
                    selected: sortColumn,
                  );
                  if (value != null && mounted) {
                    setState(() => sortColumn = value);
                  }
                }),
              ),
            ),
            Tooltip(
              message: ascending
                  ? 'Ascending; switch to descending'
                  : 'Descending; switch to ascending',
              child: _ToolbarIconPill(
                icon: ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                semanticsLabel: ascending
                    ? 'Ascending; switch to descending'
                    : 'Descending; switch to ascending',
                onTap: withFeedback(
                  () => setState(() => ascending = !ascending),
                ),
              ),
            ),
            if (narrow)
              _ViewSegmentedControl(
                tableView: tableView,
                onChanged: (next) {
                  ActionFeedback.tap();
                  setState(() => tableView = next);
                },
              ),
            _ToolbarPill(
              icon: LucideIcons.calendarDays,
              label: 'Date & time',
              onTap: withFeedback(formats),
            ),
            _ToolbarPill(
              icon: LucideIcons.listChecks,
              label: selection ? 'Done' : 'Select',
              active: selection,
              onTap: list.isEmpty && !selection
                  ? null
                  : withFeedback(() {
                      setState(() {
                        selection = !selection;
                        selected.clear();
                      });
                    }),
            ),
          ],
        ),
        SizeTransitionPanel(
          alignment: Alignment.topCenter,
          child: filtersExpanded
              ? Surface(
                  padding: const EdgeInsets.all(14),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'FILTER BY',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (hasActiveQuery)
                            InkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: withFeedback(resetFilters),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Reset',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (c, constraints) {
                          final twoCol = constraints.maxWidth >= 230;
                          final itemWidth = twoCol
                              ? (constraints.maxWidth - 10) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: itemWidth,
                                child: selectField('Month', month, [
                                  'All months',
                                  ...months,
                                ], (v) => setState(() => month = v)),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: selectField('Type', kind, [
                                  'All types',
                                  ...types,
                                ], (v) => setState(() => kind = v)),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: selectField('Weekday', weekday, [
                                  'All weekdays',
                                  'Monday',
                                  'Tuesday',
                                  'Wednesday',
                                  'Thursday',
                                  'Friday',
                                  'Saturday',
                                  'Sunday',
                                ], (v) => setState(() => weekday = v)),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: selectField('Notes', notes, [
                                  'All notes',
                                  'With notes',
                                  'Without notes',
                                ], (v) => setState(() => notes = v)),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (hasActiveQuery && !filtersExpanded)
          Align(
            alignment: Alignment.centerLeft,
            child: _ToolbarPill(
              icon: LucideIcons.x,
              label: 'Clear filters & search',
              onTap: withFeedback(resetFilters),
            ),
          ),
        SizeTransitionPanel(
          alignment: Alignment.topCenter,
          child: selection
              ? Surface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                        children: [
                          _ToolbarPill(
                            icon:
                                selected.length == list.length &&
                                    list.isNotEmpty
                                ? LucideIcons.square
                                : LucideIcons.checkCheck,
                            label:
                                selected.length == list.length &&
                                    list.isNotEmpty
                                ? 'Clear selection'
                                : 'Select visible',
                            onTap: list.isEmpty
                                ? null
                                : withFeedback(() {
                                    setState(() {
                                      if (selected.length == list.length) {
                                        selected.clear();
                                      } else {
                                        selected.addAll(list.map((s) => s.id));
                                      }
                                    });
                                  }),
                          ),
                          if (selected.isNotEmpty)
                            Material(
                              color: colors.error,
                              borderRadius: BorderRadius.circular(99),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(99),
                                onTap: withFeedback(bulkDelete),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.trash2,
                                        size: 14,
                                        color: colors.onError,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Delete ${selected.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onError,
                                        ),
                                      ),
                                    ],
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
        Row(
          children: [
            Expanded(
              child: Text(
                '${list.length} ${list.length == 1 ? 'record' : 'records'} · ${elapsed(totalSeconds)} total',
                style: TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (list.isEmpty)
          const Surface(
            child: EmptyState(
              'No matching sessions.',
              'Adjust the filters or record your first hours.',
              LucideIcons.table2,
            ),
          )
        else if (showList)
          _buildSessionList(c, list, maxListHeight)
        else
          _buildSessionTable(c, list, colors, dark),
        if (!showList && list.isNotEmpty)
          Text(
            'Scroll sideways for more columns. Drag a header divider to resize neighbouring columns; double tap it to reset.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildSessionList(
    BuildContext c,
    List<Session> list,
    double maxHeight,
  ) {
    final child = Scrollbar(
      controller: recordScroll,
      child: ListView.separated(
        controller: recordScroll,
        primary: false,
        shrinkWrap: list.length <= 6,
        padding: const EdgeInsets.only(right: 4),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (c, index) {
          final s = list[index];
          return sessionTile(
            c,
            ref,
            widget.data,
            s,
            selecting: selection,
            selected: selected.contains(s.id),
            onTapOverride: selection ? () => _toggleSelected(s.id) : null,
          );
        },
      ),
    );
    if (list.length <= 6) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      );
    }
    return SizedBox(height: maxHeight, child: child);
  }

  Widget _buildSessionTable(
    BuildContext c,
    List<Session> list,
    ColorScheme colors,
    bool dark,
  ) {
    final totalWidth = widths.fold(0.0, (a, b) => a + b) + (selection ? 48 : 0);
    return Surface(
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      child: SizedBox(
        height: math.min(368.0, list.length * 56.0 + 48.0),
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

class _SessionSummaryCard extends StatelessWidget {
  final bool filtered, hasLive;
  final int count, days, totalSeconds;
  final List<MapEntry<String, int>> breakdown;
  const _SessionSummaryCard({
    required this.filtered,
    required this.count,
    required this.days,
    required this.totalSeconds,
    required this.hasLive,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext c) {
    final avg = count == 0 ? 0 : totalSeconds ~/ count;
    return Semantics(
      container: true,
      label:
          '${filtered ? 'Filtered sessions' : 'All sessions'}: ${sessionDurationLabel(totalSeconds)}, $count sessions across $days days',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff191b19), Color(0xff303630)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    filtered ? 'FILTERED SESSIONS' : 'SESSION SUMMARY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 10,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFF34C759).withValues(alpha: .35),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF6CE59E),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 5, height: 5),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Color(0xFF8CF0B5),
                            fontSize: 9.5,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '$count ${count == 1 ? 'session' : 'sessions'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .55),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sessionDurationLabel(totalSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Geist Mono',
                        fontSize: 32,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                ),
                if (totalSeconds > 0) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      elapsed(totalSeconds),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontFamily: 'Geist Mono',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (breakdown.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      for (var i = 0; i < breakdown.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: math.max(1, breakdown[i].value),
                          child: ColoredBox(
                            color: sessionTypeColor(breakdown[i].key, true),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
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
                            color: sessionTypeColor(entry.key, true),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${entry.key} ${sessionDurationLabel(entry.value)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SessionMetric(
                    label: 'Sessions',
                    value: '$count',
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SessionMetric(
                    label: 'Average',
                    value: count == 0 ? '0m' : sessionDurationLabel(avg),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SessionMetric(
                    label: 'Days',
                    value: '$days',
                    numeric: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionMetric extends StatelessWidget {
  final String label, value;
  final bool numeric;
  const _SessionMetric({
    required this.label,
    required this.value,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .065),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white.withValues(alpha: .05)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .55),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontFamily: numeric ? 'Geist' : 'Geist Mono',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ToolbarPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailingIcon;
  final bool active;
  final VoidCallback? onTap;
  const _ToolbarPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingIcon,
    this.active = false,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final disabled = onTap == null;
    final bg = active ? colors.primary : colors.surface;
    final fg = active
        ? colors.onPrimary
        : disabled
        ? colors.onSurfaceVariant.withValues(alpha: .45)
        : colors.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 13, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconPill extends StatelessWidget {
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback? onTap;
  const _ToolbarIconPill({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Icon(icon, size: 14, color: colors.onSurface),
          ),
        ),
      ),
    );
  }
}

class _ViewSegmentedControl extends StatelessWidget {
  final bool tableView;
  final ValueChanged<bool> onChanged;
  const _ViewSegmentedControl({
    required this.tableView,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentButton(
            icon: LucideIcons.list,
            tooltip: 'List view',
            selected: !tableView,
            onTap: () => onChanged(false),
          ),
          _SegmentButton(
            icon: LucideIcons.table2,
            tooltip: 'Table view',
            selected: tableView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.duration(c, 160),
            curve: Motion.curve,
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? colors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .07),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 14,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
