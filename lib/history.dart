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
  static const defaults = [150.0, 90.0, 110.0, 110.0, 120.0, 240.0];
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
      builder: (c, setLocal) => PanelContent(
        header: Text(
          'Make dates your own.',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in [
              'EEE, d MMM',
              'dd/MM/yyyy',
              'MM/dd/yyyy',
              'd MMM yyyy',
              'yyyy-MM-dd',
              'relative',
            ])
              ListTile(
                title: Text(
                  f == 'relative'
                      ? 'Relative · 2 days ago'
                      : DateFormat(f).format(DateTime.now()),
                ),
                subtitle: Text(f),
                trailing: (widget.data.prefs['dateFormat'] ?? 'EEE, d MMM') == f
                    ? const Icon(LucideIcons.check, size: 18)
                    : null,
                onTap: withFeedback(() async {
                  await ref.read(databaseProvider).pref('dateFormat', f);
                  if (c.mounted) {
                    Navigator.pop(c);
                  }
                }),
              ),
            const Divider(),
            Wrap(
              spacing: 8,
              children: ['12', '24']
                  .map(
                    (f) => ChoiceChip(
                      label: Text(
                        '$f-hour · ${DateFormat(f == '12' ? 'h:mm a' : 'HH:mm').format(DateTime.now())}',
                      ),
                      selected: (widget.data.prefs['clockFormat'] ?? '24') == f,
                      onSelected: (_) async {
                        ActionFeedback.tap();
                        await ref.read(databaseProvider).pref('clockFormat', f);
                        if (c.mounted) {
                          Navigator.pop(c);
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
  );
  int get activeFilters => [
    month != 'All months',
    kind != 'All types',
    weekday != 'All weekdays',
    notes != 'All notes',
  ].where((v) => v).length;

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
    await guarded(context, () async {
      final db = ref.read(databaseProvider);
      await (db.delete(db.sessions)..where((s) => s.id.isIn(selected))).go();
      setState(() {
        selected.clear();
        selection = false;
      });
    }, success: 'Selected sessions deleted');
  }

  @override
  Widget build(BuildContext c) {
    final filterWidth = math.min(
      170.0,
      (MediaQuery.sizeOf(c).width -
              (MediaQuery.sizeOf(c).width < 380 ? 44 : 60)) /
          2,
    );
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
    return PageBody(
      title: 'SESSIONS',
      subtitle: 'Session history',
      children: [
        if ((AutomationSync.config(widget.data)['rules'] as List? ?? [])
            .isNotEmpty)
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.workflow, size: 20),
              title: const Text('Automation rules saved'),
              subtitle: const Text(
                'Review rules and Run/Stop status in Syntax builder',
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: withFeedback(() => openSyntaxBuilder(c)),
            ),
          ),
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Search dates, types and notes',
            prefixIcon: const Icon(LucideIcons.search, size: 20),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: withFeedback(() {
                      search.clear();
                      setState(() {});
                    }),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
          ),
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: withFeedback(
                () => setState(() => filtersExpanded = !filtersExpanded),
              ),
              icon: Icon(
                filtersExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.slidersHorizontal,
                size: 16,
              ),
              label: Text(
                activeFilters == 0 ? 'Filters' : 'Filters · $activeFilters',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                onPressed: withFeedback(() async {
                  final value = await panel<String>(
                    c,
                    _ChoiceSheet(
                      title: 'Sort sessions',
                      selected: headers[sortColumn],
                      values: headers,
                    ),
                  );
                  if (value != null && mounted) {
                    setState(() => sortColumn = headers.indexOf(value));
                  }
                }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sort: ${headers[sortColumn]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronDown, size: 14),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: ascending
                  ? 'Ascending; switch to descending'
                  : 'Descending; switch to ascending',
              onPressed: withFeedback(
                () => setState(() => ascending = !ascending),
              ),
              icon: Icon(
                ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 18,
              ),
            ),
          ],
        ),
        SizeTransitionPanel(
          alignment: Alignment.topCenter,
          child: filtersExpanded
              ? Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: filterWidth,
                      child: selectField('Month', month, [
                        'All months',
                        ...months,
                      ], (v) => setState(() => month = v)),
                    ),
                    SizedBox(
                      width: filterWidth,
                      child: selectField('Type', kind, [
                        'All types',
                        ...types,
                      ], (v) => setState(() => kind = v)),
                    ),
                    SizedBox(
                      width: filterWidth,
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
                      width: filterWidth,
                      child: selectField('Notes', notes, [
                        'All notes',
                        'With notes',
                        'Without notes',
                      ], (v) => setState(() => notes = v)),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        if (activeFilters > 0 || search.text.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: withFeedback(resetFilters),
              icon: const Icon(LucideIcons.x, size: 16),
              label: const Text('Clear filters & search'),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: withFeedback(formats),
              icon: const Icon(LucideIcons.calendarDays, size: 16),
              label: const Text('Date & time'),
            ),
            if (MediaQuery.sizeOf(c).width < 600 && !selection)
              OutlinedButton.icon(
                onPressed: withFeedback(
                  () => setState(() => tableView = !tableView),
                ),
                icon: Icon(
                  tableView ? LucideIcons.list : LucideIcons.table2,
                  size: 16,
                ),
                label: Text(tableView ? 'List view' : 'Table view'),
              ),
            OutlinedButton.icon(
              onPressed: withFeedback(
                list.isEmpty && !selection
                    ? null
                    : () => setState(() {
                        selection = !selection;
                        selected.clear();
                      }),
              ),
              icon: const Icon(LucideIcons.listChecks, size: 16),
              label: Text(selection ? 'Done selecting' : 'Select'),
            ),
            if (selection)
              OutlinedButton(
                onPressed: withFeedback(
                  () => setState(() => selected.addAll(list.map((s) => s.id))),
                ),
                child: const Text('Select visible'),
              ),
            if (selected.isNotEmpty)
              FilledButton(
                onPressed: withFeedback(bulkDelete),
                child: Text('Delete ${selected.length}'),
              ),
          ],
        ),
        Text(
          '${list.length} records · ${elapsed(list.fold(0, (sum, s) => sum + durationOf(s)))} total',
          style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 12),
        ),
        if (list.isEmpty)
          const Surface(
            child: EmptyState(
              'No matching sessions.',
              'Adjust the filters or record your first hours.',
              LucideIcons.table2,
            ),
          )
        else if (MediaQuery.sizeOf(c).width < 600 && !tableView && !selection)
          SizedBox(
            height: math.min(
              MediaQuery.sizeOf(c).height * .5,
              list.length * 112.0,
            ),
            child: Scrollbar(
              controller: recordScroll,
              child: ListView.separated(
                controller: recordScroll,
                primary: false,
                padding: const EdgeInsets.only(right: 4),
                itemCount: list.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (c, index) =>
                    sessionTile(c, ref, widget.data, list[index]),
              ),
            ),
          )
        else
          Surface(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: math.min(360.0, (list.length + 1) * 58.0 + 30),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                primary: false,
                child: SizedBox(
                  width:
                      widths.fold(0.0, (a, b) => a + b) + (selection ? 48 : 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (selection) const SizedBox(width: 48),
                          ...List.generate(
                            6,
                            (i) => SizedBox(
                              width: widths[i],
                              height: 52,
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
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                headers[i],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            if (sortColumn == i)
                                              Icon(
                                                ascending
                                                    ? LucideIcons.arrowUp
                                                    : LucideIcons.arrowDown,
                                                size: 12,
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
                                          setState(
                                            () => widths = [...defaults],
                                          );
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
                                              width: 1,
                                              height: 24,
                                              color: Theme.of(c)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: .2),
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
                      SizedBox(
                        height: math.min(308.0, list.length * 58.0),
                        child: ListView.builder(
                          primary: false,
                          physics: const ClampingScrollPhysics(),
                          itemCount: list.length,
                          itemExtent: 58,
                          itemBuilder: (c, n) {
                            final s = list[n];
                            final values = [
                              sessionDate(widget.data, s),
                              s.kind,
                              clockTime(widget.data, s.started),
                              s.ended == null
                                  ? 'Running'
                                  : clockTime(widget.data, s.ended!),
                              elapsed(durationOf(s)),
                              s.note.isEmpty ? '—' : s.note,
                            ];
                            return InkWell(
                              onTap: withFeedback(() {
                                if (selection) {
                                  setState(() {
                                    selected.contains(s.id)
                                        ? selected.remove(s.id)
                                        : selected.add(s.id);
                                  });
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
                                  color: selected.contains(s.id)
                                      ? Theme.of(c).colorScheme.primary
                                            .withValues(alpha: .08)
                                      : n.isOdd
                                      ? Theme.of(c).colorScheme.onSurface
                                            .withValues(alpha: .025)
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    if (selection)
                                      SizedBox(
                                        width: 48,
                                        child: Checkbox(
                                          value: selected.contains(s.id),
                                          onChanged: (v) => setState(() {
                                            ActionFeedback.tap();
                                            v!
                                                ? selected.add(s.id)
                                                : selected.remove(s.id);
                                          }),
                                        ),
                                      ),
                                    ...List.generate(
                                      6,
                                      (i) => SizedBox(
                                        width: widths[i],
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Text(
                                            values[i],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: i == 1 || i == 5
                                                  ? 'Geist'
                                                  : 'Geist Mono',
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
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
          ),
        if (tableView || selection || MediaQuery.sizeOf(c).width >= 600)
          const Text(
            'Scroll sideways for more columns. Scroll inside the table for more records. Drag a header divider to resize neighbouring columns; double tap it to reset.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }
}
