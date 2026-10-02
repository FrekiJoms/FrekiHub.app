part of 'screens.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  final AppData data;
  const BudgetScreen({super.key, required this.data});
  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  Future<void> occurrence(Projection p) => panel(
    context,
    Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(p.rule.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text('${p.day} · ${money(p.amount, widget.data.currency)}'),
          const SizedBox(height: 20),
          if (p.status != 'complete')
            FilledButton(
              onPressed: withFeedback(
                p.amount == 0
                    ? null
                    : () async {
                        final db = ref.read(databaseProvider);
                        await guarded(context, () async {
                          await db.transaction(() async {
                            await db
                                .into(db.entries)
                                .insert(
                                  Entry(
                                    id: newId(),
                                    day: p.day,
                                    kind: p.rule.kind,
                                    amount: p.amount,
                                    currency: p.rule.currency,
                                    category: p.rule.category,
                                    method: p.rule.method,
                                    note: p.rule.title,
                                    occurrence: p.key,
                                  ),
                                  mode: InsertMode.insertOrIgnore,
                                );
                            await db.pref('status:${p.key}', 'planned');
                          });
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        }, success: 'Recorded exactly once');
                      },
              ),
              child: const Text('Mark complete & record'),
            ),
          if (p.status != 'complete')
            ...['skipped', 'cancelled', 'planned'].map(
              (s) => TextButton(
                onPressed: withFeedback(() async {
                  await ref.read(databaseProvider).pref('status:${p.key}', s);
                  if (mounted) {
                    Navigator.pop(context);
                  }
                }),
                child: Text(s == 'planned' ? 'Reset to planned' : 'Mark $s'),
              ),
            ),
          TextButton(
            onPressed: withFeedback(() => Navigator.pop(context)),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
  Future<void> ruleMenu(Rule r) => panel(
    context,
    Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: withFeedback(() {
              Navigator.pop(context);
              panel(context, RuleForm(data: widget.data, rule: r));
            }),
            child: const Text('Edit rule'),
          ),
          TextButton(
            onPressed: withFeedback(() async {
              final db = ref.read(databaseProvider);
              await db
                  .into(db.rules)
                  .insert(
                    r.copyWith(
                      id: newId(),
                      title: '${r.title} copy',
                      position: widget.data.rules.length,
                    ),
                  );
              if (mounted) {
                Navigator.pop(context);
              }
            }),
            child: const Text('Duplicate'),
          ),
          TextButton(
            onPressed: withFeedback(() async {
              if (!await confirm(
                context,
                'Delete planner rule?',
                'Its completed transactions remain in your records.',
              )) {
                return;
              }
              final db = ref.read(databaseProvider);
              await (db.delete(db.rules)..where((t) => t.id.equals(r.id))).go();
              if (mounted) {
                Navigator.pop(context);
              }
            }),
            child: Text(
              'Delete rule',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final month = dayKey(period).substring(0, 7);
    final last = DateTime(period.year, period.month + 1, 0);
    final income = d.total('income', month: month),
        expenses = d.total('expense', month: month),
        savings = d.total('savings', month: month);
    final net = income - expenses - savings;
    final planned = project(d, period, last);
    final today = dayKey(DateTime.now());
    final commitments = planned
        .where(
          (p) =>
              p.day.compareTo(today) >= 0 &&
              p.status == 'planned' &&
              p.rule.kind != 'income',
        )
        .fold(0, (sum, p) => sum + p.amount);
    final safe = math.max(0, net - commitments);
    final used = period.isAfter(DateTime.now())
        ? 0.0
        : last.isBefore(DateTime.now())
        ? 1.0
        : DateTime.now().day / last.day;
    final goal = int.tryParse(d.prefs['savingsGoal:${d.currency}'] ?? '') ?? 0;
    final saved = d.total('savings');
    final breakdown = <String, int>{};
    for (final e in d.entries.where(
      (e) =>
          e.currency == d.currency &&
          e.day.startsWith(month) &&
          e.kind == 'expense',
    )) {
      breakdown.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final categories = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rules = d.rules.where((r) => r.currency == d.currency).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final timeline = <String, List<Widget>>{};
    void add(String day, Widget row) =>
        timeline.putIfAbsent(day, () => []).add(row);
    for (final e in d.entries.where(
      (e) => e.currency == d.currency && e.day.startsWith(month),
    )) {
      add(
        e.day,
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: withFeedback(
            () => panel(
              c,
              EntryForm(data: d, day: e.day, kind: e.kind, entry: e),
            ),
          ),
          leading: Icon(
            e.kind == 'income'
                ? LucideIcons.arrowDownLeft
                : e.kind == 'savings'
                ? LucideIcons.piggyBank
                : LucideIcons.arrowUpRight,
            size: 20,
          ),
          title: Text(e.note.isEmpty ? e.category : e.note),
          subtitle: Text('Actual · ${e.category} · ${e.method}'),
          trailing: Text(
            '${e.kind == 'income' ? '+' : '−'}${money(e.amount, d.currency)}',
            style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 12),
          ),
        ),
      );
    }
    for (final p in planned) {
      if (p.status == 'complete') continue;
      add(
        p.day,
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: withFeedback(() => occurrence(p)),
          leading: Icon(
            p.status == 'complete'
                ? LucideIcons.circleCheck
                : p.status == 'planned'
                ? LucideIcons.calendarClock
                : LucideIcons.circleMinus,
            size: 20,
          ),
          title: Text(p.rule.title),
          subtitle: Text('Expected · ${p.status} · ${p.rule.category}'),
          trailing: Text(
            money(p.amount, d.currency),
            style: TextStyle(
              fontFamily: 'Geist Mono',
              fontSize: 12,
              color: Theme.of(c).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final days = timeline.keys.toList()..sort();
    return PageBody(
      title: 'Budget.',
      subtitle: 'Your money, clearly',
      action: IconButton(
        tooltip: 'Add transaction',
        onPressed: withFeedback(() => quickAdd(c, d, today)),
        icon: const Icon(LucideIcons.plus),
      ),
      children: [
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: withFeedback(
                  () => setState(
                    () => period = DateTime(period.year, period.month - 1),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(period),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: withFeedback(
                  () => setState(
                    () => period = DateTime(period.year, period.month + 1),
                  ),
                ),
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NET POSITION',
                          style: TextStyle(fontSize: 11, letterSpacing: 2),
                        ),
                        const SizedBox(height: 12),
                        NumberValue(money(net, d.currency), size: 34),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: used,
                            strokeWidth: 5,
                            backgroundColor: Theme.of(c)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                        Text(
                          '${(used * 100).round()}%',
                          style: const TextStyle(
                            fontFamily: 'Geist Mono',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${DateFormat('MMM').format(period)} · ${last.day} days · ${(used * 100).round()}% of period elapsed',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(),
              const Text(
                'Safe to spend',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              NumberValue(money(safe, d.currency), size: 30),
              const SizedBox(height: 8),
              Text(
                'After ${money(commitments, d.currency)} in remaining planned expenses and savings.',
                style: TextStyle(
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (c, constraints) {
                  final columns = constraints.maxWidth < 260 ? 2 : 3;
                  final width =
                      (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      for (final value in [
                        ('Income', income),
                        ('Spent', expenses),
                        ('Saved', savings),
                      ])
                        SizedBox(
                          width: width,
                          child: metric(
                            c,
                            value.$1,
                            money(value.$2, d.currency),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'Savings goal',
                trailing: IconButton(
                  tooltip: 'Set savings goal',
                  onPressed: withFeedback(() => savingsGoal(c)),
                  icon: const Icon(LucideIcons.pencilLine, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              NumberValue(money(saved, d.currency), size: 28),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: goal <= 0 ? 0 : (saved / goal).clamp(0, 1),
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                goal <= 0
                    ? 'Set a goal to see your progress.'
                    : 'of ${money(goal, d.currency)} · ${math.min(100, (saved * 100 / goal).round())}% saved',
              ),
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('Where it went'),
              if (categories.isEmpty)
                const EmptyState(
                  'No spending this month.',
                  'Expenses will show here by category.',
                  LucideIcons.chartPie,
                )
              else ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: Semantics(
                    label:
                        'Category spending total ${money(expenses, d.currency)}',
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 44,
                        sectionsSpace: 4,
                        sections: List.generate(
                          categories.length,
                          (i) => PieChartSectionData(
                            value: categories[i].value.toDouble(),
                            color: Design.chart[i % Design.chart.length],
                            radius: 24,
                            showTitle: false,
                          ),
                        ),
                        pieTouchData: PieTouchData(enabled: true),
                      ),
                      duration: Motion.duration(c),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(
                  categories.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Design.chart[i % Design.chart.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(categories[i].key)),
                            Text(
                              money(categories[i].value, d.currency),
                              style: const TextStyle(
                                fontFamily: 'Geist Mono',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: categories[i].value / expenses,
                            minHeight: 4,
                            color: Design.chart[i % Design.chart.length],
                            backgroundColor: Theme.of(c)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SectionHeading(
          'Give your money a plan.',
          trailing: IconButton(
            tooltip: 'Add planner rule',
            onPressed: withFeedback(() => panel(c, RuleForm(data: d))),
            icon: const Icon(LucideIcons.plus),
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: rules.isEmpty
              ? const EmptyState(
                  'A plan starts with one rule.',
                  'Add payday savings, rent, or a daily allowance.',
                  LucideIcons.calendarClock,
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: rules.length,
                  onReorderItem: (old, next) async {
                    final reordered = [...rules];
                    reordered.insert(next, reordered.removeAt(old));
                    final db = ref.read(databaseProvider);
                    await db.transaction(() async {
                      for (var i = 0; i < reordered.length; i++) {
                        await (db.update(db.rules)
                              ..where((r) => r.id.equals(reordered[i].id)))
                            .write(RulesCompanion(position: Value(i)));
                      }
                    });
                  },
                  itemBuilder: (c, i) {
                    final r = rules[i];
                    return ListTile(
                      key: ValueKey(r.id),
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.title),
                      subtitle: Text(
                        '${r.cadence} · ${r.basis == 'fixed' ? money(r.amount * r.quantity, d.currency) : '${editableMoney(r.amount, 'PHP')}% of ${r.basis} × ${r.quantity}'}',
                      ),
                      onTap: withFeedback(() => ruleMenu(r)),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(LucideIcons.gripVertical, size: 18),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SectionHeading('Expected & actual'),
        if (days.isEmpty)
          const Surface(
            child: EmptyState(
              'A clean slate.',
              'Add a transaction or a planner rule.',
              LucideIcons.wallet,
            ),
          )
        else
          ...days.map(
            (day) => Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE, d MMMM').format(calendarDate(day)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...timeline[day]!,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget metric(BuildContext c, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(c).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 14),
        ),
      ),
    ],
  );
  Future<void> savingsGoal(BuildContext c) async {
    final field = TextEditingController(
      text: editableMoney(
        int.tryParse(
              widget.data.prefs['savingsGoal:${widget.data.currency}'] ?? '',
            ) ??
            0,
        widget.data.currency,
      ),
    );
    await panel(
      c,
      StatefulBuilder(
        builder: (c, setLocal) {
          String? error;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Savings goal', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextField(
                  controller: field,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Goal · ${widget.data.currency}',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: withFeedback(() async {
                    try {
                      final amount = parseMoney(
                        field.text,
                        widget.data.currency,
                      );
                      await ref
                          .read(databaseProvider)
                          .pref('savingsGoal:${widget.data.currency}', amount);
                      if (c.mounted) {
                        Navigator.pop(c);
                      }
                    } on FormatException catch (e) {
                      if (c.mounted) {
                        toast(c, e.message);
                      }
                    }
                  }),
                  child: const Text('Save goal'),
                ),
              ],
            ),
          );
        },
      ),
    );
    field.dispose();
  }
}
