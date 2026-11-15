part of 'screens.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  final AppData data;
  const CalendarScreen({super.key, required this.data});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _viewNames = ['year', 'month', 'week', 'day'];
  static const _hourHeight = 56.0;
  static const _timeGutter = 44.0;

  late DateTime selected;
  late int mode;
  late bool collapsed;
  late bool labels;
  final sessionsByDay = <String, List<Session>>{};
  final entriesByDay = <String, List<Entry>>{};
  final ScrollController _weekScroll = ScrollController();

  String? storedSelection;
  String? _lastWeekScrollKey;
  int _periodDir = 0;
  int _agendaDir = 0;
  double _collapseDragDy = 0;
  bool _collapseHandledInDrag = false;

  @override
  void initState() {
    super.initState();
    selected = _dayOnly(
      DateTime.tryParse(widget.data.prefs['calendarSelected'] ?? '') ??
          DateTime.now(),
    );
    final savedMode = _viewNames.indexOf(
      widget.data.prefs['calendarView'] ?? 'month',
    );
    mode = savedMode == -1 ? 1 : savedMode;
    collapsed = widget.data.prefs['calendarCollapsed'] == '1';
    labels = widget.data.prefs['calendarLabels'] == '1';
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

  @override
  void dispose() {
    _weekScroll.dispose();
    super.dispose();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday % 7));

  void indexRecords() {
    sessionsByDay.clear();
    entriesByDay.clear();
    for (final s in widget.data.sessions) {
      sessionsByDay.putIfAbsent(s.day, () => []).add(s);
    }
    for (final list in sessionsByDay.values) {
      list.sort((a, b) => a.started.compareTo(b.started));
    }
    for (final e in widget.data.entries) {
      entriesByDay.putIfAbsent(e.day, () => []).add(e);
    }
    for (final list in entriesByDay.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
  }

  List<Session> sessions(DateTime date) =>
      sessionsByDay[dayKey(date)] ?? const [];

  List<Entry> entries(DateTime date) => entriesByDay[dayKey(date)] ?? const [];

  List<String> records(DateTime date) => [
    ...sessions(date).map((s) => s.kind),
    ...entries(date).map((e) => e.category),
  ];

  void _selectDate(DateTime next, {int? nextMode}) {
    final normalized = _dayOnly(next);
    final dir = normalized.compareTo(_dayOnly(selected));
    setState(() {
      _agendaDir = dir == 0 ? 0 : (dir > 0 ? 1 : -1);
      if (nextMode != null && nextMode != mode) {
        _periodDir = 0;
        mode = nextMode;
      } else {
        _periodDir = _agendaDir;
      }
      selected = normalized;
    });
  }

  void _jumpToToday() {
    final now = _dayOnly(DateTime.now());
    final dir = now.compareTo(_dayOnly(selected));
    setState(() {
      _periodDir = dir == 0 ? 0 : (dir > 0 ? 1 : -1);
      _agendaDir = _periodDir;
      selected = now;
    });
  }

  void _setCollapsed(bool next, {bool haptic = true}) {
    if (collapsed == next) return;
    if (haptic) HapticFeedback.selectionClick();
    setState(() => collapsed = next);
    unawaited(
      ref
          .read(databaseProvider)
          .pref('calendarCollapsed', next ? '1' : '0')
          .catchError((Object _) {}),
    );
  }

  void shift(int direction) => setState(() {
    _periodDir = direction.sign;
    _agendaDir = direction.sign;
    if (mode == 0) {
      final targetYear = selected.year + direction;
      final lastDay = DateTime(targetYear, selected.month + 1, 0).day;
      selected = DateTime(
        targetYear,
        selected.month,
        math.min(selected.day, lastDay),
      );
    } else if (mode == 1) {
      final rawMonth = DateTime(selected.year, selected.month + direction, 1);
      final lastDay = DateTime(rawMonth.year, rawMonth.month + 1, 0).day;
      selected = DateTime(
        rawMonth.year,
        rawMonth.month,
        math.min(selected.day, lastDay),
      );
    } else {
      selected = DateTime(
        selected.year,
        selected.month,
        selected.day + direction * (mode == 2 ? 7 : 1),
      );
    }
  });

  void _handleHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 240) return;
    ActionFeedback.tap();
    shift(velocity < 0 ? 1 : -1);
  }

  void _syncWeekScrollPosition(DateTime start) {
    if (mode != 2) return;
    final weekKey = dayKey(start);
    if (_lastWeekScrollKey == weekKey) return;
    _lastWeekScrollKey = weekKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || mode != 2 || !_weekScroll.hasClients) return;
      int? earliestHour;
      for (var i = 0; i < 7; i++) {
        final d = DateTime(start.year, start.month, start.day + i);
        for (final s in sessions(d)) {
          final h = DateTime.fromMillisecondsSinceEpoch(s.started).hour;
          if (earliestHour == null || h < earliestHour) earliestHour = h;
        }
      }
      final targetHour = earliestHour == null
          ? 7.0
          : math.max(0.0, earliestHour - 1.0);
      final maxExtent = _weekScroll.position.maxScrollExtent;
      final offset = (targetHour * _hourHeight).clamp(0.0, maxExtent);
      _weekScroll.jumpTo(offset);
    });
  }

  String _periodTitle() => switch (mode) {
    0 => '${selected.year}',
    3 => DateFormat('MMMM yyyy').format(selected),
    _ => DateFormat('MMMM yyyy').format(selected),
  };

  String _periodSummary() {
    var sessionCount = 0;
    var totalSeconds = 0;
    var entryCount = 0;
    void addDay(DateTime d) {
      final ss = sessions(d);
      final es = entries(d);
      sessionCount += ss.length;
      for (final s in ss) {
        totalSeconds += durationOf(s);
      }
      entryCount += es.length;
    }

    if (mode == 0) {
      for (var m = 1; m <= 12; m++) {
        final days = DateTime(selected.year, m + 1, 0).day;
        for (var d = 1; d <= days; d++) {
          addDay(DateTime(selected.year, m, d));
        }
      }
    } else if (mode == 1) {
      final days = DateTime(selected.year, selected.month + 1, 0).day;
      for (var d = 1; d <= days; d++) {
        addDay(DateTime(selected.year, selected.month, d));
      }
    } else if (mode == 2) {
      final start = _weekStart(selected);
      for (var i = 0; i < 7; i++) {
        addDay(DateTime(start.year, start.month, start.day + i));
      }
    } else {
      addDay(selected);
    }
    if (sessionCount == 0 && entryCount == 0) {
      return switch (mode) {
        0 => 'No records this year',
        1 => 'No records this month',
        2 => 'No records this week',
        _ => 'No records on this day',
      };
    }
    final parts = <String>[];
    if (sessionCount > 0) {
      parts.add(
        '$sessionCount ${sessionCount == 1 ? 'session' : 'sessions'} · ${sessionDurationLabel(totalSeconds)}',
      );
    }
    if (entryCount > 0) {
      parts.add('$entryCount ${entryCount == 1 ? 'entry' : 'entries'}');
    }
    return parts.join('  •  ');
  }

  Widget _directionalSlideFade({
    required BuildContext context,
    required Key currentKey,
    required int direction,
    required Widget child,
    double slideFraction = 0.12,
  }) {
    final dur = Motion.duration(context);
    return AnimatedSwitcher(
      duration: dur,
      reverseDuration: Motion.duration(context, 180),
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        if (dur == Duration.zero || direction == 0) {
          return FadeTransition(opacity: animation, child: child);
        }
        final isCurrent = child.key == currentKey;
        final dx = isCurrent
            ? direction * slideFraction
            : -direction * slideFraction;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(dx, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext c) {
    final signature = '${dayKey(selected)}:$mode';
    if (storedSelection != signature) {
      storedSelection = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final db = ref.read(databaseProvider);
          unawaited(
            (() async {
              await db.pref('calendarSelected', dayKey(selected));
              await db.pref('calendarView', _viewNames[mode]);
            })().catchError((Object _) {}),
          );
        }
      });
    }

    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final today = _dayOnly(DateTime.now());
    final isTodaySelected = _isSameDay(selected, today);
    final modeUnit = ['year', 'month', 'week', 'day'][mode];
    final viewKey = ValueKey('view:$mode');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          const PageTitle('CALENDAR'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _periodTitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.35,
                            ),
                          ),
                        ),
                        if (!isTodaySelected) ...[
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: 'Jump to today',
                            excludeSemantics: true,
                            child: Material(
                              color: colors.primary.withValues(
                                alpha: dark ? 0.20 : 0.11,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: withFeedback(_jumpToToday),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    'Today',
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _periodSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Chrome(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous $modeUnit',
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: withFeedback(() => shift(-1)),
                      icon: const Icon(LucideIcons.chevronLeft, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Next $modeUnit',
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: withFeedback(() => shift(1)),
                      icon: const Icon(LucideIcons.chevronRight, size: 17),
                    ),
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Calendar options',
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: withFeedback(() async {
                          final option = await showChoiceMenu<String>(
                            anchor,
                            choices: {
                              'today': 'Go to today',
                              'labels': labels
                                  ? 'Show record dots'
                                  : 'Show record labels',
                            },
                            selected: '',
                          );
                          if (!mounted || option == null) return;
                          if (option == 'today') {
                            _jumpToToday();
                          } else if (option == 'labels') {
                            setState(() => labels = !labels);
                            unawaited(
                              ref
                                  .read(databaseProvider)
                                  .pref('calendarLabels', labels ? '1' : '0')
                                  .catchError((Object _) {}),
                            );
                          }
                        }),
                        icon: const Icon(LucideIcons.ellipsis, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CalendarModeControl(
            index: mode,
            onChanged: (next) {
              if (next == mode) return;
              ActionFeedback.tap();
              setState(() {
                _periodDir = 0;
                _lastWeekScrollKey = null;
                mode = next;
              });
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.duration(c),
              reverseDuration: Motion.duration(c, 180),
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.curve,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: viewKey,
                child: switch (mode) {
                  0 => _buildYearView(c),
                  2 => _buildWeekView(c),
                  3 => _buildDayView(c),
                  _ => _buildMonthView(c),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearView(BuildContext c) {
    final yearKey = ValueKey('year:${selected.year}');
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: _directionalSlideFade(
        context: c,
        currentKey: yearKey,
        direction: _periodDir,
        child: KeyedSubtree(
          key: yearKey,
          child: LayoutBuilder(
            builder: (c, constraints) {
              final textScale = MediaQuery.textScalerOf(c).scale(1);
              final cols = constraints.maxWidth < 290 ? 2 : 3;
              const spacing = 10.0;
              final tileWidth =
                  (constraints.maxWidth - spacing * (cols - 1)) / cols;
              final miniCell = math.max(
                14.0,
                ((tileWidth - 16) / 7).clamp(14.0, 26.0),
              );
              final headerHeight = 26.0 + (textScale - 1).clamp(0, 0.8) * 10;
              final weekdayHeight = 14.0 + (textScale - 1).clamp(0, 0.8) * 5;
              final tileHeight =
                  16 +
                  headerHeight +
                  4 +
                  weekdayHeight +
                  4 +
                  (miniCell * 6) +
                  4;
              final aspectRatio = (tileWidth / tileHeight).clamp(0.55, 1.2);
              final bottomClearance = MediaQuery.viewPaddingOf(c).bottom + 96;

              return GridView.builder(
                padding: EdgeInsets.only(bottom: bottomClearance),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: 12,
                itemBuilder: (c, idx) => _buildYearMonthCard(
                  c,
                  DateTime(selected.year, idx + 1),
                  miniCell,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildYearMonthCard(
    BuildContext c,
    DateTime first,
    double miniCellHeight,
  ) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final today = _dayOnly(DateTime.now());
    final isCurrentMonth =
        first.year == today.year && first.month == today.month;
    final isSelectedMonth =
        first.year == selected.year && first.month == selected.month;
    final offset = first.weekday % 7;
    final length = DateTime(first.year, first.month + 1, 0).day;
    var recordCount = 0;
    for (var day = 1; day <= length; day++) {
      final d = DateTime(first.year, first.month, day);
      recordCount += sessions(d).length + entries(d).length;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isCurrentMonth
            ? Border.all(
                color: colors.primary.withValues(alpha: dark ? 0.50 : 0.40),
                width: 1.2,
              )
            : isSelectedMonth
            ? Border.all(color: colors.outline.withValues(alpha: 0.45))
            : null,
      ),
      child: Surface(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: withFeedback(() {
                _periodDir = 0;
                setState(() {
                  selected = DateTime(
                    first.year,
                    first.month,
                    math.min(selected.day, length),
                  );
                  mode = 1;
                });
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          DateFormat('MMM').format(first),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isCurrentMonth
                                ? colors.primary
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (recordCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(
                            alpha: dark ? 0.22 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$recordCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: List.generate(
                7,
                (i) => Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            ...List.generate(6, (r) {
              return SizedBox(
                height: miniCellHeight,
                child: Row(
                  children: List.generate(7, (w) {
                    final index = r * 7 + w - offset + 1;
                    if (index < 1 || index > length) {
                      return const Expanded(child: SizedBox());
                    }
                    final d = DateTime(first.year, first.month, index);
                    final isToday = _isSameDay(d, today);
                    final isSel = _isSameDay(d, selected);
                    final hasRecords =
                        sessions(d).isNotEmpty || entries(d).isNotEmpty;
                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: withFeedback(() {
                          _periodDir = 0;
                          setState(() {
                            selected = d;
                            mode = 1;
                          });
                        }),
                        child: Center(
                          child: Container(
                            width: miniCellHeight - 1,
                            height: miniCellHeight - 1,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSel
                                  ? colors.primary
                                  : isToday
                                  ? colors.primary.withValues(
                                      alpha: dark ? 0.25 : 0.14,
                                    )
                                  : hasRecords
                                  ? colors.secondary.withValues(
                                      alpha: dark ? 0.16 : 0.09,
                                    )
                                  : null,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(1.5),
                                child: Text(
                                  '$index',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSel || isToday
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? colors.onPrimary
                                        : isToday
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthView(BuildContext c) {
    final first = DateTime(selected.year, selected.month, 1);
    final offset = first.weekday % 7;
    final length = DateTime(selected.year, selected.month + 1, 0).day;
    final rows = ((offset + length) / 7).ceil();
    final selectedRow = ((offset + selected.day - 1) ~/ 7).clamp(0, rows - 1);
    final gridStart = DateTime(selected.year, selected.month, 1 - offset);
    final monthKey = ValueKey('month:${selected.year}-${selected.month}');
    final colors = Theme.of(c).colorScheme;
    final dur = Motion.duration(c);

    return LayoutBuilder(
      builder: (c, constraints) {
        final compactHeight = constraints.maxHeight < 360;
        final single = collapsed || compactHeight;
        final textScale = MediaQuery.textScalerOf(c).scale(1);
        final minCell = (labels ? 52.0 : 42.0) + (textScale - 1) * 8;
        final maxGridBudget =
            constraints.maxHeight * (compactHeight ? .45 : .58);
        final rowHeight = (maxGridBudget / rows).clamp(
          minCell,
          labels ? 96.0 : 72.0,
        );
        final gridHeight = single ? rowHeight : rowHeight * rows;

        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _handleHorizontalSwipe,
              onVerticalDragStart: (_) {
                _collapseDragDy = 0;
                _collapseHandledInDrag = false;
              },
              onVerticalDragUpdate: (d) {
                if (compactHeight || _collapseHandledInDrag) return;
                _collapseDragDy += d.delta.dy;
                if (_collapseDragDy <= -22 && !collapsed) {
                  _collapseHandledInDrag = true;
                  _setCollapsed(true);
                } else if (_collapseDragDy >= 22 && collapsed) {
                  _collapseHandledInDrag = true;
                  _setCollapsed(false);
                }
              },
              onVerticalDragEnd: (d) {
                if (compactHeight || _collapseHandledInDrag) return;
                final v = d.primaryVelocity ?? 0;
                if (v < -260 && !collapsed) {
                  _setCollapsed(true);
                } else if (v > 260 && collapsed) {
                  _setCollapsed(false);
                }
              },
              child: Surface(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWeekdayStrip(c, constraints.maxWidth),
                    const SizedBox(height: 6),
                    _directionalSlideFade(
                      context: c,
                      currentKey: monthKey,
                      direction: _periodDir,
                      child: KeyedSubtree(
                        key: monthKey,
                        child: ClipRect(
                          child: AnimatedContainer(
                            duration: dur,
                            curve: Motion.curve,
                            height: gridHeight,
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: List.generate(rows, (r) {
                                final hidden = single && r != selectedRow;
                                final targetTop = single
                                    ? (r - selectedRow) * rowHeight
                                    : r * rowHeight;
                                return AnimatedPositioned(
                                  duration: dur,
                                  curve: Motion.curve,
                                  left: 0,
                                  right: 0,
                                  top: targetTop,
                                  height: rowHeight,
                                  child: IgnorePointer(
                                    ignoring: hidden,
                                    child: AnimatedOpacity(
                                      duration: dur,
                                      curve: Motion.curve,
                                      opacity: hidden ? 0.0 : 1.0,
                                      child: Row(
                                        children: List.generate(7, (w) {
                                          final d = DateTime(
                                            gridStart.year,
                                            gridStart.month,
                                            gridStart.day + r * 7 + w,
                                          );
                                          return Expanded(
                                            child: _buildMonthDayCell(
                                              c,
                                              d,
                                              currentMonth:
                                                  d.month == selected.month,
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: single
                          ? 'Expand month grid'
                          : 'Collapse month grid',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: compactHeight
                            ? null
                            : withFeedback(() => _setCollapsed(!collapsed)),
                        child: SizedBox(
                          height: 26,
                          width: double.infinity,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 34,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: colors.outline.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              if (!compactHeight) ...[
                                const SizedBox(width: 6),
                                AnimatedRotation(
                                  turns: single ? 0.5 : 0.0,
                                  duration: dur,
                                  curve: Motion.curve,
                                  child: Icon(
                                    LucideIcons.chevronUp,
                                    size: 13,
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _buildAgendaSection(c)),
          ],
        );
      },
    );
  }

  Widget _buildWeekdayStrip(BuildContext c, double availableWidth) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final today = _dayOnly(DateTime.now());
    final full = availableWidth >= 340
        ? const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final todayColumn =
        selected.year == today.year && selected.month == today.month
        ? today.weekday % 7
        : -1;

    return Row(
      children: List.generate(7, (i) {
        final isWeekend = i == 0 || i == 6;
        final isTodayCol = i == todayColumn;
        return Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                full[i],
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isTodayCol ? FontWeight.w700 : FontWeight.w600,
                  color: isTodayCol
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(
                          alpha: isWeekend ? 0.65 : 0.88,
                        ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMonthDayCell(
    BuildContext c,
    DateTime date, {
    required bool currentMonth,
  }) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final today = _dayOnly(DateTime.now());
    final isSelected = _isSameDay(date, selected);
    final isToday = _isSameDay(date, today);
    final daySessions = sessions(date);
    final dayEntries = entries(date);
    final items = records(date);

    return Semantics(
      selected: isSelected,
      button: true,
      label:
          '${DateFormat('EEEE, d MMMM yyyy').format(date)}, ${items.length} records',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: withFeedback(() => _selectDate(date)),
        onLongPress: withFeedback(
          () => panel(c, DayPanel(day: dayKey(date), initialData: widget.data)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: Motion.duration(c, 160),
                curve: Motion.curve,
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? colors.primary
                      : isToday
                      ? colors.primary.withValues(alpha: dark ? 0.24 : 0.13)
                      : Colors.transparent,
                  border: isToday && !isSelected
                      ? Border.all(
                          color: colors.primary.withValues(alpha: 0.45),
                          width: 1,
                        )
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.0,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? colors.onPrimary
                            : isToday
                            ? colors.primary
                            : colors.onSurface.withValues(
                                alpha: currentMonth ? 1.0 : 0.36,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 3),
                if (labels)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (c, labelSpace) {
                        final visibleCount = labelSpace.maxHeight >= 30 ? 2 : 1;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final text in items.take(visibleCount))
                              Flexible(
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 1.5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: dark ? 0.22 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      height: 1.1,
                                      fontWeight: FontWeight.w600,
                                      color: currentMonth
                                          ? colors.onSurface
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  )
                else
                  _buildRecordDots(
                    c,
                    daySessions,
                    dayEntries,
                    dark: dark,
                    isSelected: isSelected,
                    dimmed: !currentMonth,
                  ),
              ] else
                const SizedBox(height: 7),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordDots(
    BuildContext c,
    List<Session> daySessions,
    List<Entry> dayEntries, {
    required bool dark,
    required bool isSelected,
    required bool dimmed,
  }) {
    final colors = Theme.of(c).colorScheme;
    final dotColors = <Color>[
      for (final s in daySessions.take(2)) sessionTypeColor(s.kind, dark),
      for (final e in dayEntries.take(2)) _entryColor(colors, e, dark),
    ];
    final alpha = dimmed ? 0.45 : 0.92;
    return SizedBox(
      height: 7,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < dotColors.take(4).length; i++) ...[
              if (i > 0) const SizedBox(width: 2.5),
              Container(
                width: 4.5,
                height: 4.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColors[i].withValues(alpha: alpha),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(BuildContext c) {
    final start = _weekStart(selected);
    _syncWeekScrollPosition(start);
    final weekKey = ValueKey('week:${dayKey(start)}');
    final colors = Theme.of(c).colorScheme;
    final dark = themeBrightness(c);
    final theme = Theme.of(c);
    final today = _dayOnly(DateTime.now());
    final now = DateTime.now();
    final bottomClearance = MediaQuery.viewPaddingOf(c).bottom + 96;

    return _directionalSlideFade(
      context: c,
      currentKey: weekKey,
      direction: _periodDir,
      child: KeyedSubtree(
        key: weekKey,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _handleHorizontalSwipe,
              child: Surface(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: _timeGutter - 6,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'ALL',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        ...List.generate(7, (i) {
                          final d = DateTime(
                            start.year,
                            start.month,
                            start.day + i,
                          );
                          final isToday = _isSameDay(d, today);
                          final isSel = _isSameDay(d, selected);
                          final dayEntries = entries(d);
                          return Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: withFeedback(() {
                                _selectDate(d);
                                panel(
                                  c,
                                  DayPanel(
                                    day: dayKey(d),
                                    initialData: widget.data,
                                  ),
                                );
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: isSel
                                      ? colors.primary.withValues(
                                          alpha: dark ? 0.16 : 0.08,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        DateFormat('E').format(d),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isToday
                                                  ? colors.primary
                                                  : colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isToday
                                            ? colors.primary
                                            : Colors.transparent,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${d.day}',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: isToday
                                                    ? colors.onPrimary
                                                    : colors.onSurface,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    SizedBox(
                                      height: 15,
                                      child: dayEntries.isEmpty
                                          ? const SizedBox.shrink()
                                          : Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: colors.secondary
                                                      .withValues(
                                                        alpha: dark
                                                            ? 0.24
                                                            : 0.14,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    dayEntries.length == 1
                                                        ? dayEntries
                                                              .first
                                                              .category
                                                        : '${dayEntries.length} tx',
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: colors.onSurface,
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
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Surface(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SingleChildScrollView(
                    controller: _weekScroll,
                    padding: EdgeInsets.only(bottom: bottomClearance),
                    child: LayoutBuilder(
                      builder: (c, box) {
                        final colWidth = (box.maxWidth - _timeGutter) / 7;
                        final nowY = (now.hour + now.minute / 60) * _hourHeight;
                        return SizedBox(
                          height: 24 * _hourHeight,
                          child: Stack(
                            children: [
                              for (var h = 0; h < 24; h++)
                                Positioned(
                                  top: h * _hourHeight,
                                  left: 0,
                                  right: 0,
                                  height: _hourHeight,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: _timeGutter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                            right: 6,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              '${h.toString().padLeft(2, '0')}:00',
                                              textAlign: TextAlign.right,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    fontSize: 9.5,
                                                    color: colors
                                                        .onSurfaceVariant
                                                        .withValues(
                                                          alpha: 0.72,
                                                        ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: colors.outline
                                                    .withValues(alpha: 0.22),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              for (var i = 0; i < 7; i++)
                                ..._buildWeekColumn(
                                  c,
                                  DateTime(
                                    start.year,
                                    start.month,
                                    start.day + i,
                                  ),
                                  i,
                                  colWidth,
                                  isToday: _isSameDay(
                                    DateTime(
                                      start.year,
                                      start.month,
                                      start.day + i,
                                    ),
                                    today,
                                  ),
                                  nowY: nowY,
                                  dark: dark,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildWeekColumn(
    BuildContext c,
    DateTime date,
    int colIndex,
    double colWidth, {
    required bool isToday,
    required double nowY,
    required bool dark,
  }) {
    final colors = Theme.of(c).colorScheme;
    final colLeft = _timeGutter + colIndex * colWidth;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayStartMs = dayStart.millisecondsSinceEpoch;
    final dayEndMs = dayEnd.millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final rawBlocks = <_WeekBlock>[];
    for (final s in widget.data.sessions) {
      final startMs = math.max(s.started, dayStartMs);
      final endMs = math.min(s.ended ?? nowMs, dayEndMs);
      if (endMs <= startMs) continue;
      final startMin = (startMs - dayStartMs) / 60000;
      final endMin = math.max(startMin + 24, (endMs - dayStartMs) / 60000);
      rawBlocks.add(_WeekBlock(session: s, startMin: startMin, endMin: endMin));
    }

    final placed = _assignWeekLanes(rawBlocks);

    return [
      Positioned(
        left: colLeft,
        top: 0,
        width: colWidth,
        height: 24 * _hourHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: withFeedback(() {
            _selectDate(date);
            quickAdd(c, widget.data, dayKey(date));
          }),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isToday
                  ? colors.primary.withValues(alpha: dark ? 0.06 : 0.03)
                  : null,
              border: Border(
                left: BorderSide(color: colors.outline.withValues(alpha: 0.22)),
              ),
            ),
          ),
        ),
      ),
      for (final b in placed)
        Positioned(
          left: colLeft + b.lane * (colWidth / b.laneCount) + 1.5,
          top: (b.startMin / 60) * _hourHeight,
          width: math.max(12.0, (colWidth / b.laneCount) - 3),
          height: math.max(22.0, ((b.endMin - b.startMin) / 60) * _hourHeight),
          child: _buildWeekSessionBlock(c, b.session, dark),
        ),
      if (isToday)
        Positioned(
          left: colLeft - 3,
          top: nowY - 3,
          width: colWidth + 3,
          child: IgnorePointer(
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.error,
                  ),
                ),
                Expanded(child: Container(height: 1.5, color: colors.error)),
              ],
            ),
          ),
        ),
    ];
  }

  List<_PlacedWeekBlock> _assignWeekLanes(List<_WeekBlock> blocks) {
    if (blocks.isEmpty) return const [];
    final sorted = [...blocks]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    final groups = <List<_WeekBlock>>[];
    var currentGroup = <_WeekBlock>[];
    var groupEnd = -1.0;

    for (final b in sorted) {
      if (currentGroup.isEmpty || b.startMin < groupEnd) {
        currentGroup.add(b);
        groupEnd = math.max(groupEnd, b.endMin);
      } else {
        groups.add(currentGroup);
        currentGroup = [b];
        groupEnd = b.endMin;
      }
    }
    if (currentGroup.isNotEmpty) groups.add(currentGroup);

    final result = <_PlacedWeekBlock>[];
    for (final group in groups) {
      final laneEnds = <double>[];
      final assignments = <int>[];
      for (final b in group) {
        var placedLane = -1;
        for (var l = 0; l < laneEnds.length; l++) {
          if (laneEnds[l] <= b.startMin) {
            placedLane = l;
            laneEnds[l] = b.endMin;
            break;
          }
        }
        if (placedLane == -1) {
          placedLane = laneEnds.length;
          laneEnds.add(b.endMin);
        }
        assignments.add(placedLane);
      }
      final laneCount = laneEnds.length;
      for (var i = 0; i < group.length; i++) {
        result.add(
          _PlacedWeekBlock(
            session: group[i].session,
            startMin: group[i].startMin,
            endMin: group[i].endMin,
            lane: assignments[i],
            laneCount: laneCount,
          ),
        );
      }
    }
    return result;
  }

  Widget _buildWeekSessionBlock(BuildContext c, Session s, bool dark) {
    final accent = sessionTypeColor(s.kind, dark);
    final colors = Theme.of(c).colorScheme;
    return Material(
      color: accent.withValues(alpha: dark ? 0.28 : 0.16),
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: withFeedback(
          () =>
              panel(c, SessionForm(data: widget.data, day: s.day, session: s)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: colors.onSurface,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        clockTime(widget.data, s.started),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: colors.onSurfaceVariant,
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
    );
  }

  Widget _buildDayView(BuildContext c) {
    final dKey = ValueKey('day:${dayKey(selected)}');
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: _directionalSlideFade(
        context: c,
        currentKey: dKey,
        direction: _periodDir,
        child: KeyedSubtree(
          key: dKey,
          child: _buildAgendaSection(c, showDailyHero: true),
        ),
      ),
    );
  }

  Widget _buildDailyHero(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final today = _dayOnly(DateTime.now());
    final isToday = _isSameDay(selected, today);
    final daySessions = sessions(selected);
    final dayEntries = entries(selected);
    final totalSec = daySessions.fold<int>(0, (sum, s) => sum + durationOf(s));

    return Surface(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        DateFormat('MMMM yyyy').format(selected).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(
                            alpha: dark ? 0.22 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'TODAY',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 84),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: NumberValue(
                          '${selected.day}'.padLeft(2, '0'),
                          size: 56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('EEEE').format(selected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            daySessions.isEmpty && dayEntries.isEmpty
                                ? 'No activity recorded'
                                : [
                                    if (daySessions.isNotEmpty)
                                      '${daySessions.length} ${daySessions.length == 1 ? 'session' : 'sessions'} (${sessionDurationLabel(totalSec)})',
                                    if (dayEntries.isNotEmpty)
                                      '${dayEntries.length} ${dayEntries.length == 1 ? 'entry' : 'entries'}',
                                  ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactActionPill(
                icon: LucideIcons.plus,
                label: 'New',
                filled: true,
                onTap: () => quickAdd(c, widget.data, dayKey(selected)),
              ),
              const SizedBox(height: 8),
              _CompactActionPill(
                icon: LucideIcons.panelBottomOpen,
                label: 'All',
                onTap: () => panel(
                  c,
                  DayPanel(day: dayKey(selected), initialData: widget.data),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaSection(BuildContext c, {bool showDailyHero = false}) {
    final agendaKey = ValueKey('agenda:${dayKey(selected)}:$showDailyHero');
    final ss = sessions(selected);
    final es = entries(selected);
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final bottomClearance = MediaQuery.viewPaddingOf(c).bottom + 96;
    final isToday = _isSameDay(selected, _dayOnly(DateTime.now()));

    final content = ListView(
      key: agendaKey,
      padding: EdgeInsets.only(bottom: bottomClearance),
      children: [
        if (showDailyHero) ...[
          _buildDailyHero(c),
          const SizedBox(height: 14),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isToday ? 'Today · ' : ''}${DateFormat('EEE, d MMM').format(selected)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ss.isEmpty && es.isEmpty
                          ? 'Free day — tap New to log activity'
                          : '${ss.length} ${ss.length == 1 ? 'session' : 'sessions'} · ${es.length} ${es.length == 1 ? 'entry' : 'entries'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CompactActionPill(
                icon: LucideIcons.plus,
                label: 'New',
                filled: true,
                onTap: () => quickAdd(c, widget.data, dayKey(selected)),
              ),
              const SizedBox(width: 6),
              _CompactActionPill(
                icon: LucideIcons.panelBottomOpen,
                label: 'Sheet',
                onTap: () => panel(
                  c,
                  DayPanel(day: dayKey(selected), initialData: widget.data),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (ss.isEmpty && es.isEmpty)
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                Icon(
                  LucideIcons.calendarCheck2,
                  size: 28,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                ),
                const SizedBox(height: 10),
                Text(
                  'No records for ${DateFormat('d MMM').format(selected)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add a session, expense, income, or savings entry.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (ss.isNotEmpty) ...[
            const SectionHeading('Sessions'),
            const SizedBox(height: 6),
            for (final s in ss)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: sessionTile(c, ref, widget.data, s),
              ),
          ],
          if (es.isNotEmpty) ...[
            if (ss.isNotEmpty) const SizedBox(height: 6),
            const SectionHeading('Money'),
            const SizedBox(height: 6),
            for (final e in es)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildEntryCard(c, widget.data, e),
              ),
          ],
        ],
      ],
    );

    if (showDailyHero) return content;

    return _directionalSlideFade(
      context: c,
      currentKey: agendaKey,
      direction: _agendaDir,
      slideFraction: 0.08,
      child: content,
    );
  }
}

class _WeekBlock {
  final Session session;
  final double startMin;
  final double endMin;
  const _WeekBlock({
    required this.session,
    required this.startMin,
    required this.endMin,
  });
}

class _PlacedWeekBlock extends _WeekBlock {
  final int lane;
  final int laneCount;
  const _PlacedWeekBlock({
    required super.session,
    required super.startMin,
    required super.endMin,
    required this.lane,
    required this.laneCount,
  });
}

class _CalendarModeControl extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _CalendarModeControl({required this.index, required this.onChanged});

  static const _labels = ['Year', 'Month', 'Week', 'Day'];

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final dur = Motion.duration(c, 210);
    final alignment = Alignment(-1 + (2 * index) / (_labels.length - 1), 0);

    return Chrome(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: alignment,
              duration: dur,
              curve: Motion.curve,
              child: FractionallySizedBox(
                widthFactor: 1 / _labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    color: dark
                        ? colors.primary.withValues(alpha: 0.24)
                        : colors.surface,
                    boxShadow: dark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 6,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                  ),
                ),
              ),
            ),
            Row(
              children: List.generate(_labels.length, (i) {
                final active = i == index;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: active,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _labels[i],
                              maxLines: 1,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: active
                                    ? (dark ? colors.primary : colors.onSurface)
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const _CompactActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final fg = filled ? colors.primary : colors.onSurface;
    final bg = filled
        ? colors.primary.withValues(alpha: dark ? 0.22 : 0.12)
        : colors.surfaceContainerHighest.withValues(alpha: dark ? 0.55 : 0.65);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: withFeedback(onTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13.5, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool themeBrightness(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark;

Color _entryColor(ColorScheme colors, Entry e, bool dark) => switch (e.kind) {
  'income' => dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
  'savings' => dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
  'transfer_in' || 'transfer_out' => colors.secondary,
  _ => colors.error,
};

IconData _entryIcon(Entry e) {
  final isTransfer = e.kind == 'transfer_in' || e.kind == 'transfer_out';
  if (isTransfer) return LucideIcons.arrowLeftRight;
  return switch (e.kind) {
    'income' => LucideIcons.arrowDownLeft,
    'savings' => LucideIcons.piggyBank,
    _ => LucideIcons.arrowUpRight,
  };
}

Widget _buildEntryCard(BuildContext c, AppData d, Entry e) {
  final theme = Theme.of(c);
  final colors = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final isTransfer = e.kind == 'transfer_in' || e.kind == 'transfer_out';
  final accent = _entryColor(colors, e, dark);
  final title = isTransfer
      ? (e.kind == 'transfer_out'
            ? '${e.method} -> ${e.category}'
            : '${e.category} -> ${e.method}')
      : e.category;
  final subtitle =
      '${isTransfer ? 'transfer' : e.kind} · ${e.method}${e.note.isEmpty ? '' : ' · ${e.note}'}';
  final sign = e.kind == 'income' ? '+' : (e.kind == 'expense' ? '−' : '');

  return Surface(
    padding: EdgeInsets.zero,
    borderRadius: BorderRadius.circular(16),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_entryIcon(e), size: 17, color: accent),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        '$sign${money(e.amount, e.currency)}',
        maxLines: 1,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
      onTap: withFeedback(
        () => panel(
          c,
          isTransfer && e.occurrence != null
              ? WalletTransferSheet(data: d, existingOccurrence: e.occurrence)
              : EntryForm(
                  data: d,
                  day: e.day,
                  kind: isTransfer ? 'expense' : e.kind,
                  entry: e,
                ),
        ),
      ),
    ),
  );
}

class DayPanel extends ConsumerWidget {
  final String day;
  final AppData initialData;
  const DayPanel({super.key, required this.day, required this.initialData});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final d = ref.watch(dataProvider).value ?? initialData;
    final sessions = d.sessions.where((s) => s.day == day).toList()
      ..sort((a, b) => a.started.compareTo(b.started));
    final entries = d.entries.where((e) => e.day == day).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return PanelContent(
      scrollable: true,
      header: PanelHeading(
        title: displayDate(d, calendarDate(day)),
        trailing: _CompactActionPill(
          icon: LucideIcons.plus,
          label: 'Add',
          filled: true,
          onTap: () => quickAdd(c, d, day),
        ),
      ),
      child: ListView(
        primary: true,
        children: [
          if (sessions.isEmpty && entries.isEmpty)
            const EmptyState(
              'No records on this day',
              'Add a session or transaction using the Add button.',
              LucideIcons.calendar,
            ),
          if (sessions.isNotEmpty) ...[
            const SectionHeading('Sessions'),
            const SizedBox(height: 8),
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: sessionTile(c, ref, d, s),
              ),
          ],
          if (entries.isNotEmpty) ...[
            if (sessions.isNotEmpty) const SizedBox(height: 6),
            const SectionHeading('Money'),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildEntryCard(c, d, e),
              ),
          ],
        ],
      ),
    );
  }
}
