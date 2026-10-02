part of 'screens.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  final AppData data;
  const CalendarScreen({super.key, required this.data});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  int mode = 1;
  bool collapsed = false;
  bool labels = false;
  static const blue = Color(0xff4788ff);
  final sessionsByDay = <String, List<Session>>{};
  final entriesByDay = <String, List<Entry>>{};

  @override
  void initState() {
    super.initState();
    indexRecords();
  }

  @override
  void didUpdateWidget(CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data.sessions, widget.data.sessions) ||
        !identical(oldWidget.data.entries, widget.data.entries)) {
      indexRecords();
    }
  }

  void indexRecords() {
    sessionsByDay.clear();
    entriesByDay.clear();
    for (final s in widget.data.sessions) {
      sessionsByDay.putIfAbsent(s.day, () => []).add(s);
    }
    for (final e in widget.data.entries) {
      entriesByDay.putIfAbsent(e.day, () => []).add(e);
    }
  }

  List<Session> sessions(DateTime date) =>
      sessionsByDay[dayKey(date)] ?? const [];
  List<Entry> entries(DateTime date) => entriesByDay[dayKey(date)] ?? const [];
  List<String> records(DateTime date) => [
    ...sessions(date).map((s) => s.kind),
    ...entries(date).map((e) => e.category),
  ];
  void choose(DateTime date) => setState(() => selected = date);
  void shift(int direction) => setState(() {
    selected = mode == 0
        ? DateTime(selected.year + direction, selected.month, selected.day)
        : mode == 1
        ? DateTime(selected.year, selected.month + direction)
        : selected.add(Duration(days: direction * (mode == 2 ? 7 : 1)));
  });

  String? storedSelection;
  @override
  Widget build(BuildContext c) {
    final signature = '${dayKey(selected)}:$mode';
    if (storedSelection != signature) {
      storedSelection = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final db = ref.read(databaseProvider);
        unawaited(
          db
              .transaction(() async {
                await db.pref('calendarSelected', dayKey(selected));
                await db.pref(
                  'calendarView',
                  ['year', 'month', 'week', 'day'][mode],
                );
              })
              .catchError((Object _) {}),
        );
      });
    }
    final colors = Theme.of(c).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        80,
        16,
        112 + MediaQuery.paddingOf(c).bottom,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mode == 0
                        ? '${selected.year}'
                        : '${selected.year} / ${selected.month.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  tooltip: 'Add to selected day',
                  onPressed: withFeedback(
                    () => quickAdd(c, widget.data, dayKey(selected)),
                  ),
                  icon: const Icon(LucideIcons.plus),
                ),
                IconButton(
                  tooltip: 'Calendar options',
                  icon: const Icon(LucideIcons.ellipsisVertical),
                  onPressed: withFeedback(() async {
                    final option = await panel<String>(
                      c,
                      _ChoiceSheet(
                        title: 'Calendar options',
                        values: [
                          'Go to today',
                          labels ? 'Show record dots' : 'Show record labels',
                        ],
                      ),
                    );
                    if (option == null || !mounted) return;
                    setState(() {
                      if (option == 'Go to today') {
                        selected = DateUtils.dateOnly(DateTime.now());
                      } else {
                        labels = !labels;
                      }
                    });
                  }),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous ${['year', 'month', 'week', 'day'][mode]}',
                onPressed: withFeedback(() => shift(-1)),
                icon: const Icon(LucideIcons.chevronLeft, size: 18),
              ),
              Expanded(
                child: Text(
                  DateFormat(mode == 0 ? 'yyyy' : 'MMMM yyyy').format(selected),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next ${['year', 'month', 'week', 'day'][mode]}',
                onPressed: withFeedback(() => shift(1)),
                icon: const Icon(LucideIcons.chevronRight, size: 18),
              ),
            ],
          ),
          Expanded(
            child: mode == 0
                ? yearView(c)
                : LayoutBuilder(
                    builder: (c, constraints) {
                      final start = DateTime(selected.year, selected.month);
                      final monthStart = start.subtract(
                        Duration(days: start.weekday % 7),
                      );
                      final rows =
                          ((DateTime(selected.year, selected.month + 1, 0).day +
                                      start.weekday % 7) /
                                  7)
                              .ceil();
                      final week = selected.subtract(
                        Duration(days: selected.weekday % 7),
                      );
                      final single =
                          collapsed || mode == 2 || constraints.maxHeight < 360;
                      final rowHeight = (constraints.maxHeight * .56 / rows)
                          .clamp(48.0, labels ? 108.0 : 84.0);
                      return Column(
                        children: [
                          if (mode != 3) ...[
                            weekdays(c, false),
                            SizeTransitionPanel(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                height: rowHeight * (single ? 1 : rows),
                                child: Column(
                                  children: List.generate(
                                    single ? 1 : rows,
                                    (row) => SizedBox(
                                      height: rowHeight,
                                      child: Row(
                                        children: List.generate(
                                          7,
                                          (col) => Expanded(
                                            child: dateCell(
                                              c,
                                              (single ? week : monthStart).add(
                                                Duration(days: row * 7 + col),
                                              ),
                                              false,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: mode == 1
                                  ? (details) {
                                      if (details.delta.dy.abs() > 1) {
                                        setState(
                                          () =>
                                              collapsed = details.delta.dy < 0,
                                        );
                                      }
                                    }
                                  : null,
                              child: Semantics(
                                button: true,
                                label: collapsed
                                    ? 'Expand month'
                                    : 'Collapse to week',
                                child: InkWell(
                                  onTap: mode == 1
                                      ? withFeedback(
                                          () => setState(
                                            () => collapsed = !collapsed,
                                          ),
                                        )
                                      : null,
                                  child: SizedBox(
                                    height: 32,
                                    width: double.infinity,
                                    child: Center(
                                      child: Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: colors.onSurface.withValues(
                                            alpha: .18,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  DateFormat('EEEE, d MMMM').format(selected),
                                  style: Theme.of(c).textTheme.titleLarge,
                                ),
                              ),
                            ),
                          Expanded(
                            child: mode == 2
                                ? weekTimeline(c, week)
                                : agenda(c),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Semantics(
                    selected: mode == i,
                    child: TextButton(
                      onPressed: withFeedback(
                        () => setState(() {
                          mode = i;
                          collapsed = false;
                        }),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: mode == i
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            [
                              LucideIcons.calendarDays,
                              LucideIcons.calendar,
                              LucideIcons.columns3,
                              LucideIcons.calendarCheck,
                            ][i],
                            size: 20,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            ['Year', 'Month', 'Week', 'Day'][i],
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget weekdays(BuildContext c, bool small) => Row(
    children:
        (small
                ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                : ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'])
            .map(
              (d) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: small ? 6 : 12),
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: small ? 8 : 11,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
  );

  Widget yearView(BuildContext c) => LayoutBuilder(
    builder: (c, constraints) => SingleChildScrollView(
      child: Wrap(
        spacing: 16,
        runSpacing: 24,
        children: List.generate(12, (index) {
          final month = index + 1;
          final first = DateTime(selected.year, month);
          final offset = first.weekday % 7;
          final count = DateTime(selected.year, month + 1, 0).day;
          return SizedBox(
            width: (constraints.maxWidth - 32) / 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: withFeedback(
                    () => setState(() {
                      selected = first;
                      mode = 1;
                    }),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      DateFormat('MMM').format(first),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        color: month == selected.month ? blue : null,
                      ),
                    ),
                  ),
                ),
                weekdays(c, true),
                ...List.generate(
                  6,
                  (row) => Row(
                    children: List.generate(7, (col) {
                      final day = row * 7 + col - offset + 1;
                      return Expanded(
                        child: day < 1 || day > count
                            ? const SizedBox(height: 23)
                            : dateCell(
                                c,
                                DateTime(selected.year, month, day),
                                true,
                              ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    ),
  );

  Widget dateCell(BuildContext c, DateTime date, bool small) {
    final active = DateUtils.isSameDay(date, selected);
    final today = DateUtils.isSameDay(date, DateTime.now());
    final outside = date.month != selected.month;
    final items = records(date);
    final foreground = Theme.of(c).colorScheme.onSurface;
    final weekend = date.weekday == 6 || date.weekday == 7;
    return Semantics(
      label:
          '${DateFormat('EEEE, d MMMM yyyy').format(date)}, ${items.length} records',
      selected: active,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(small ? 4 : 12),
        onTap: withFeedback(
          () => setState(() {
            selected = date;
            if (small) mode = 1;
          }),
        ),
        onLongPress: withFeedback(
          () => panel(c, DayPanel(day: dayKey(date), initialData: widget.data)),
        ),
        child: LayoutBuilder(
          builder: (c, bounds) {
            final showLabels = labels && bounds.maxHeight >= 64;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: small
                      ? 23
                      : showLabels
                      ? 28
                      : 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active || (small && today) ? blue : null,
                    borderRadius: BorderRadius.circular(small ? 4 : 12),
                  ),
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: small ? 9 : 20,
                      fontWeight: FontWeight.w500,
                      color: active || (small && today)
                          ? Colors.white
                          : outside && !small
                          ? foreground.withValues(alpha: .25)
                          : weekend
                          ? blue
                          : foreground,
                    ),
                  ),
                ),
                if (!small && showLabels && items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 3, 2, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: blue.withValues(alpha: .24),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        items.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                if (!small && showLabels && items.length > 1)
                  Text(
                    '+${items.length - 1}',
                    style: const TextStyle(fontSize: 9, color: blue),
                  ),
                if (!small && !showLabels)
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: items.isNotEmpty
                          ? blue
                          : foreground.withValues(alpha: .2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget dailyCover(BuildContext c) => Container(
    height: MediaQuery.sizeOf(c).height * .43,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xff173b53),
          Color(0xff526c86),
          Color(0xffb59b97),
          Color(0xff314e42),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('yyyy / MM').format(selected),
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '${selected.day}',
                style: const TextStyle(
                  fontSize: 92,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                DateFormat('EEEE').format(selected),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget weekTimeline(BuildContext c, DateTime week) {
    final colors = Theme.of(c).colorScheme;
    final dates = List.generate(7, (i) => week.add(Duration(days: i)));
    final now = DateTime.now();
    const hourHeight = 56.0;
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  'Finance',
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                ),
              ),
              ...dates.map(
                (date) => Expanded(
                  child: InkWell(
                    onTap: withFeedback(() {
                      choose(date);
                      panel(
                        c,
                        DayPanel(day: dayKey(date), initialData: widget.data),
                      );
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entries(date).isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: blue.withValues(alpha: .25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entries(date).first.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          if (entries(date).length > 1)
                            Text(
                              '+${entries(date).length - 1}',
                              style: const TextStyle(fontSize: 9, color: blue),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: hourHeight * 24,
              child: LayoutBuilder(
                builder: (c, constraints) {
                  final columnWidth = (constraints.maxWidth - 40) / 7;
                  return Stack(
                    children: [
                      ...List.generate(
                        24,
                        (hour) => Positioned(
                          top: hour * hourHeight,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: colors.outlineVariant.withValues(
                                    alpha: .4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ...List.generate(
                        8,
                        (i) => Positioned(
                          left: 40 + columnWidth * i,
                          top: 0,
                          bottom: 0,
                          child: VerticalDivider(
                            width: 1,
                            color: colors.outlineVariant.withValues(alpha: .4),
                          ),
                        ),
                      ),
                      for (var i = 0; i < 7; i++)
                        ...widget.data.sessions
                            .where((s) {
                              final start = DateTime.fromMillisecondsSinceEpoch(
                                s.started,
                              );
                              final end = DateTime.fromMillisecondsSinceEpoch(
                                s.ended ?? now.millisecondsSinceEpoch,
                              );
                              return start.isBefore(
                                    dates[i].add(const Duration(days: 1)),
                                  ) &&
                                  end.isAfter(dates[i]);
                            })
                            .map((s) {
                              final start = DateTime.fromMillisecondsSinceEpoch(
                                s.started,
                              );
                              final end = DateTime.fromMillisecondsSinceEpoch(
                                s.ended ?? now.millisecondsSinceEpoch,
                              );
                              final startMinute = start.isBefore(dates[i])
                                  ? 0
                                  : start.hour * 60 + start.minute;
                              final endMinute =
                                  end.isAfter(
                                    dates[i].add(const Duration(days: 1)),
                                  )
                                  ? 1440
                                  : end.hour * 60 + end.minute;
                              final blockHeight = math.max(
                                22.0,
                                (endMinute - startMinute) / 60 * hourHeight,
                              );
                              return Positioned(
                                left: 41 + i * columnWidth,
                                width: math.max(1, columnWidth - 2),
                                top: startMinute / 60 * hourHeight,
                                height: math.min(
                                  blockHeight,
                                  24 * hourHeight -
                                      startMinute / 60 * hourHeight,
                                ),
                                child: Material(
                                  color: blue.withValues(alpha: .35),
                                  borderRadius: BorderRadius.circular(4),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: withFeedback(
                                      () => panel(
                                        c,
                                        SessionForm(
                                          data: widget.data,
                                          day: s.day,
                                          session: s,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Text(
                                        '${s.kind}\n${clockTime(widget.data, s.started)}',
                                        style: const TextStyle(fontSize: 9),
                                        overflow: TextOverflow.fade,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                      if (dates.any((d) => DateUtils.isSameDay(d, now)))
                        Positioned(
                          left: 40 + (now.weekday % 7) * columnWidth,
                          width: columnWidth,
                          top: (now.hour + now.minute / 60) * hourHeight,
                          child: const Divider(
                            height: 1,
                            thickness: 2,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget agenda(BuildContext c) {
    final ss = sessions(selected)
      ..sort((a, b) => a.started.compareTo(b.started));
    final es = entries(selected);
    final colors = Theme.of(c).colorScheme;
    Widget card(String title, String subtitle, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          minLeadingWidth: 8,
          leading: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.circle, size: 6, color: blue),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(subtitle),
          onTap: withFeedback(tap),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (mode == 3) dailyCover(c),
        if (ss.isEmpty && es.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'No records for ${DateFormat('d MMM').format(selected)}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                TextButton.icon(
                  onPressed: withFeedback(
                    () => quickAdd(c, widget.data, dayKey(selected)),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Add a record'),
                ),
              ],
            ),
          ),
        ...ss.map(
          (s) => card(
            s.note.isEmpty ? '${s.kind} session' : s.note,
            '${clockTime(widget.data, s.started)} – ${s.ended == null ? 'In progress' : clockTime(widget.data, s.ended!)}',
            () => panel(
              c,
              SessionForm(data: widget.data, day: s.day, session: s),
            ),
          ),
        ),
        ...es.map(
          (e) => card(
            e.category,
            '${e.kind} · ${money(e.amount, e.currency)}${e.note.isEmpty ? '' : ' · ${e.note}'}',
            () => panel(
              c,
              EntryForm(data: widget.data, day: e.day, kind: e.kind, entry: e),
            ),
          ),
        ),
      ],
    );
  }
}

class DayPanel extends ConsumerStatefulWidget {
  final String day;
  final AppData initialData;
  const DayPanel({super.key, required this.day, required this.initialData});
  @override
  ConsumerState<DayPanel> createState() => _DayPanelState();
}

class _DayPanelState extends ConsumerState<DayPanel> {
  Timer? resizeTimer;
  double? extent;
  late AppDatabase database;
  @override
  void initState() {
    super.initState();
    database = ref.read(databaseProvider);
  }

  void persistExtent() {
    if (extent != null) {
      unawaited(database.pref('dayPanel', extent!).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    resizeTimer?.cancel();
    persistExtent();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final day = widget.day;
    final d = ref.watch(dataProvider).value ?? widget.initialData;
    final height = (double.tryParse(d.prefs['dayPanel'] ?? '') ?? .65).clamp(
      .3,
      .95,
    );
    final sessions = d.sessions.where((s) => s.day == day).toList();
    final entries = d.entries.where((e) => e.day == day).toList();
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        extent = n.extent;
        resizeTimer?.cancel();
        resizeTimer = Timer(const Duration(milliseconds: 250), persistExtent);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: height,
        minChildSize: .3,
        maxChildSize: .95,
        expand: false,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
          children: [
            Center(
              child: Text(
                DateFormat('EEEE, d MMMM yyyy').format(calendarDate(day)),
                style: Theme.of(c).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: withFeedback(() => quickAdd(c, d, day)),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Add to this day'),
            ),
            const SizedBox(height: 24),
            const SectionHeading('Sessions'),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const Text('No hours recorded.')
            else
              ...sessions.map((s) => sessionTile(c, ref, d, s)),
            const Divider(),
            const SectionHeading('Money'),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('No transactions recorded.')
            else
              ...entries.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: withFeedback(
                    () => panel(
                      c,
                      EntryForm(data: d, day: day, kind: e.kind, entry: e),
                    ),
                  ),
                  leading: Icon(
                    e.kind == 'income'
                        ? LucideIcons.arrowDownLeft
                        : e.kind == 'savings'
                        ? LucideIcons.piggyBank
                        : LucideIcons.arrowUpRight,
                  ),
                  title: Text(e.category),
                  subtitle: Text(
                    '${e.kind} · ${e.method}${e.note.isEmpty ? '' : '\n${e.note}'}',
                  ),
                  trailing: Text(
                    money(e.amount, e.currency),
                    style: const TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
