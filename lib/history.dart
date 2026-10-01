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
  bool ascending = false, selection = false;
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
      final comparison = av is int
          ? av.compareTo(bv as int)
          : (av as String).compareTo(bv as String);
      return ascending ? comparison : -comparison;
    });
    return list;
  }

  Future<void> formats() => panel(
    context,
    StatefulBuilder(
      builder: (c, setLocal) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Make dates your own.',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
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
      title: 'Time, accounted for.',
      subtitle: 'Session history',
      action: IconButton(
        tooltip: 'Add session',
        onPressed: withFeedback(
          () => panel(
            c,
            SessionForm(data: widget.data, day: dayKey(DateTime.now())),
          ),
        ),
        icon: const Icon(LucideIcons.plus),
      ),
      children: [
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 170,
              child: selectField('Month', month, [
                'All months',
                ...months,
              ], (v) => setState(() => month = v)),
            ),
            SizedBox(
              width: 150,
              child: selectField('Type', kind, [
                'All types',
                ...types,
              ], (v) => setState(() => kind = v)),
            ),
            SizedBox(
              width: 170,
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
              width: 150,
              child: selectField('Notes', notes, [
                'All notes',
                'With notes',
                'Without notes',
              ], (v) => setState(() => notes = v)),
            ),
          ],
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
            OutlinedButton.icon(
              onPressed: withFeedback(
                () => setState(() {
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
        else
          Surface(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: math.min(620.0, (list.length + 1) * 58.0 + 30),
              child: InteractiveViewer(
                constrained: false,
                minScale: .6,
                maxScale: 2.5,
                boundaryMargin: const EdgeInsets.all(24),
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
                        height: math.min(538.0, list.length * 58.0),
                        child: ListView.builder(
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
        const Text(
          'Pinch to zoom, drag to pan. Drag a header divider to resize neighbouring columns; double tap it to reset.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
