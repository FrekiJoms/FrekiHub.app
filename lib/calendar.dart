part of 'screens.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  final AppData data;
  const CalendarScreen({super.key, required this.data});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  int year = DateTime.now().year;
  final filters = {'sessions', 'expense', 'income'};
  String? pulse;
  int pulseVersion = 0;
  @override
  void didUpdateWidget(CalendarScreen old) {
    super.didUpdateWidget(old);
    final newIds = widget.data.entries
        .where((e) => !old.data.entries.any((p) => p.id == e.id))
        .toList();
    if (newIds.isNotEmpty) {
      pulse = newIds.last.day;
      pulseVersion++;
    }
    final newSessions = widget.data.sessions
        .where((e) => !old.data.sessions.any((p) => p.id == e.id))
        .toList();
    if (newSessions.isNotEmpty) {
      pulse = newSessions.last.day;
      pulseVersion++;
    }
  }

  void openDay(String day) =>
      panel(context, DayPanel(day: day, initialData: widget.data));
  void monthSummary(int month) {
    final controller = PageController(initialPage: month - 1);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close month summary',
      barrierColor: Colors.black.withValues(alpha: .3),
      transitionDuration: Motion.duration(context),
      transitionBuilder: (c, a, b, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(
            begin: .96,
            end: 1.0,
          ).animate(CurvedAnimation(parent: a, curve: Motion.curve)),
          child: child,
        ),
      ),
      pageBuilder: (c, a, b) => Center(
        child: SizedBox(
          height: 460,
          width: math.min(MediaQuery.sizeOf(c).width - 32, 520),
          child: PageView.builder(
            controller: controller,
            itemCount: 12,
            itemBuilder: (c, i) {
              final key = '$year-${(i + 1).toString().padLeft(2, '0')}';
              final d = widget.data;
              final income = d.total('income', month: key),
                  expense = d.total('expense', month: key);
              final count = DateTime(year, i + 2, 0).day;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Material(
                  color: Colors.transparent,
                  child: Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('MMMM yyyy')
                                    .format(DateTime(year, i + 1)),
                                style: Theme.of(c).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(c),
                              icon: const Icon(LucideIcons.x),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text('Income  ${money(income, d.currency)}'),
                        const SizedBox(height: 8),
                        Text('Spending  ${money(expense, d.currency)}'),
                        const SizedBox(height: 8),
                        Text(
                          'Net  ${money(income - expense, d.currency)}',
                          style: const TextStyle(fontFamily: 'Geist Mono'),
                        ),
                        const SizedBox(height: 26),
                        const Text('Session hours by day'),
                        const SizedBox(height: 16),
                        Expanded(
                          child: BarChart(
                            BarChartData(
                              barTouchData: BarTouchData(enabled: true),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              barGroups: List.generate(count, (day) {
                                final dk =
                                    '$key-${(day + 1).toString().padLeft(2, '0')}';
                                final hours =
                                    d.sessions
                                        .where((s) => s.day == dk)
                                        .fold(
                                          0,
                                          (sum, s) => sum + durationOf(s),
                                        ) /
                                    3600;
                                return BarChartGroupData(
                                  x: day + 1,
                                  barRods: [
                                    BarChartRodData(
                                      toY: hours,
                                      color: Theme.of(c).colorScheme.primary,
                                      width: 4,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ],
                                );
                              }),
                            ),
                            duration: Motion.duration(c),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'Swipe to explore another month',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => PageBody(
    title: '$year, at a glance.',
    subtitle: 'Your year in days',
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous year',
          onPressed: () => setState(() => year--),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        IconButton(
          tooltip: 'Next year',
          onPressed: () => setState(() => year++),
          icon: const Icon(LucideIcons.chevronRight),
        ),
      ],
    ),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ['sessions', 'expense', 'income']
            .map(
              (f) => BounceFilterChip(
                label: Text(
                  f == 'sessions'
                      ? 'OJT & sessions'
                      : f == 'expense'
                      ? 'Expenses'
                      : 'Income',
                ),
                selected: filters.contains(f),
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    v ? filters.add(f) : filters.remove(f);
                  });
                },
              ),
            )
            .toList(),
      ),
      LayoutBuilder(
        builder: (c, constraints) {
          final columns = constraints.maxWidth >= 750
              ? 4
              : constraints.maxWidth >= 480
              ? 3
              : 2;
          final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 20,
            children: List.generate(
              12,
              (i) => SizedBox(
                width: width,
                child: Surface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => monthSummary(i + 1),
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('MMMM')
                                      .format(DateTime(year, i + 1)),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(LucideIcons.arrowUpRight, size: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: 'MTWTFSS'
                            .split('')
                            .map(
                              (s) => Expanded(
                                child: Text(
                                  s,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      monthGrid(c, i + 1),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      const Text(
        'Tap a date for details. Tap a month for its summary.',
        style: TextStyle(fontSize: 12),
      ),
      OutlinedButton.icon(
        onPressed: () => quickAdd(c, widget.data, dayKey(DateTime.now())),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Add a record'),
      ),
    ],
  );
  Widget monthGrid(BuildContext c, int month) {
    final offset = DateTime(year, month).weekday - 1;
    final days = DateTime(year, month + 1, 0).day;
    return Column(
      children: List.generate(
        6,
        (row) => Row(
          children: List.generate(7, (column) {
            final day = row * 7 + column - offset + 1;
            if (day < 1 || day > days) {
              return const Expanded(child: SizedBox(height: 28));
            }
            final key = dayKey(DateTime(year, month, day));
            final session =
                filters.contains('sessions') &&
                widget.data.sessions.any((s) => s.day == key);
            final expense =
                filters.contains('expense') &&
                widget.data.entries.any(
                  (e) =>
                      e.day == key &&
                      e.kind == 'expense' &&
                      e.currency == widget.data.currency,
                );
            final income =
                filters.contains('income') &&
                widget.data.entries.any(
                  (e) =>
                      e.day == key &&
                      e.kind == 'income' &&
                      e.currency == widget.data.currency,
                );
            final today = key == dayKey(DateTime.now());
            return Expanded(
              child: Semantics(
                label:
                    '$key${session ? ', has sessions' : ''}${expense ? ', expenses' : ''}${income ? ', income' : ''}',
                button: true,
                child: InkWell(
                  onTap: () => openDay(key),
                  borderRadius: BorderRadius.circular(14),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('$key:${pulse == key ? pulseVersion : 0}'),
                    tween: Tween(begin: pulse == key ? 1.3 : 1, end: 1),
                    curve: Motion.settle,
                    duration: Motion.duration(c, 500),
                    builder: (c, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: today ? Theme.of(c).colorScheme.primary : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Geist Mono',
                              color: today
                                  ? Theme.of(c).colorScheme.onPrimary
                                  : null,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (session) mark(c, today, 0),
                              if (expense) mark(c, today, 1),
                              if (income) mark(c, today, 2),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget mark(BuildContext c, bool today, int kind) => Container(
    width: kind == 0 ? 4 : 3,
    height: 3,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(
      color: today
          ? Theme.of(c).colorScheme.onPrimary
          : kind == 0
          ? Theme.of(c).colorScheme.primary
          : Design.chart[kind],
      shape: kind == 1 ? BoxShape.rectangle : BoxShape.circle,
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
    final height = (double.tryParse(d.prefs['dayPanel'] ?? '') ?? .65).clamp(
      .3,
      .95,
    );
    final sessions = d.sessions.where((s) => s.day == day).toList();
    final entries = d.entries
        .where((e) => e.day == day && e.currency == d.currency)
        .toList();
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        ref.read(databaseProvider).pref('dayPanel', n.extent);
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
              onPressed: () => quickAdd(c, d, day),
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
                  onTap: () => panel(
                    c,
                    EntryForm(data: d, day: day, kind: e.kind, entry: e),
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
                    money(e.amount, d.currency),
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
