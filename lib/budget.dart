part of 'screens.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  final AppData data;
  const BudgetScreen({super.key, required this.data});
  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  String? wallet;
  bool masked = false;
  final ScrollController _scrollController = ScrollController();
  bool _showCompactBalance = false;
  Future<void> occurrence(Projection p) => panel(
    context,
    PanelContent(
      header: PanelHeading(title: p.rule.title),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${p.day} · ${p.error == null ? money(p.amount, widget.data.currency) : 'Amount needs review'}',
          ),
          if (p.error != null) Text(p.error!),
          const SizedBox(height: 20),
          if (p.status != 'complete')
            FilledButton(
              onPressed: withFeedback(
                p.amount == 0 || p.error != null
                    ? null
                    : () async {
                        final db = ref.read(databaseProvider);
                        await guarded(
                          context,
                          () async {
                            await saveWithLocation(
                              context,
                              db,
                              () => db.recordProjection(p),
                            );
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          },
                          success: 'Recorded exactly once',
                          successIcon: DataAction.saved.icon,
                        );
                      },
              ),
              child: const Text('Mark complete & record'),
            ),
          if (p.status != 'complete')
            ...['skipped', 'cancelled', 'planned'].map(
              (s) => TextButton(
                onPressed: withFeedback(() async {
                  await guarded(
                    context,
                    () async {
                      await ref
                          .read(databaseProvider)
                          .pref('status:${p.key}', s);
                      if (mounted) Navigator.pop(context);
                    },
                    success: s == 'planned'
                        ? 'Planner item reset to planned'
                        : 'Planner item marked $s',
                    successIcon: DataAction.updated.icon,
                  );
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
    PanelContent(
      header: PanelHeading(title: r.title),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              await guarded(
                context,
                () async {
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
                },
                success: 'Planner rule duplicated',
                successIcon: DataAction.duplicated.icon,
              );
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
              if (!mounted) return;
              final db = ref.read(databaseProvider);
              await guarded(
                context,
                () async {
                  await (db.delete(
                    db.rules,
                  )..where((t) => t.id.equals(r.id))).go();
                  if (mounted) Navigator.pop(context);
                },
                success: 'Planner rule deleted',
                successIcon: DataAction.deleted.icon,
              );
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
  void initState() {
    super.initState();
    masked = widget.data.prefs['walletMasked'] == 'true';
    _scrollController.addListener(() {
      final show = _scrollController.offset > 100;
      if (show != _showCompactBalance && mounted) {
        setState(() => _showCompactBalance = show);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleMasked() {
    setState(() => masked = !masked);
    unawaited(
      ref
          .read(databaseProvider)
          .pref('walletMasked', '$masked')
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final month = dayKey(period).substring(0, 7);
    final last = DateTime(period.year, period.month + 1, 0);
    final plannedForPeriod = project(d, period, last);
    final planned = wallet == null
        ? plannedForPeriod
        : plannedForPeriod
              .where((p) => walletMethodName(p.rule.method) == wallet)
              .toList();
    final summary = financeMonth(d, period, wallet, planned);
    final committed = walletCommitments(plannedForPeriod);
    final goal = int.tryParse(d.prefs['savingsGoal:${d.currency}'] ?? '') ?? 0;
    final saved = wallet == null
        ? d.total('savings')
        : d
              .scopedEntries(wallet: wallet)
              .where((e) => e.kind == 'savings')
              .fold(0, (sum, e) => sum + e.amount);
    final savingsEntries = d.savingsByWallet.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final breakdown = <String, int>{};
    for (final e in d.scopedEntries(wallet: wallet, month: month).where(
      (e) => e.kind == 'expense',
    )) {
      breakdown.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final categories = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rules =
        (wallet == null
              ? d.rules.where((r) => r.currency == d.currency)
              : d.rules.where(
                  (r) =>
                      r.currency == d.currency &&
                      walletMethodName(r.method) == wallet,
                ))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final timeline = <String, List<Widget>>{};
    void add(String day, Widget row) =>
        timeline.putIfAbsent(day, () => []).add(row);
    for (final e in d.scopedEntries(wallet: wallet, month: month)) {
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
          subtitle: Text(
            'Expected · ${p.status} · ${p.rule.category} · ${p.rule.method}',
          ),
          trailing: Text(
            p.error == null ? money(p.amount, d.currency) : 'Needs review',
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
    final accounts = walletAccounts(widget.data);
    final totalBalance = accounts
        .where((a) => a.included)
        .fold<int>(0, (sum, a) => sum + a.balance);
    return Stack(
      children: [
        PageBody(
          scrollController: _scrollController,
          children: [
            const SizedBox(height: 72),
            WalletSection(
              data: d,
              month: summary,
              wallet: wallet,
              committed: committed,
              maskedOverride: masked,
              onPeriod: (next) =>
                  setState(() => period = DateTime(next.year, next.month)),
              onWallet: (name) => setState(() => wallet = name),
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
              Text(
                wallet == null
                    ? 'SAVED · ALL WALLETS'
                    : 'SAVED · ${wallet!.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, letterSpacing: 1.6),
              ),
              const SizedBox(height: 8),
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
                    : 'of ${money(goal, d.currency)} · ${math.min(100, (saved * 100 / goal).round())}% saved${wallet == null ? '' : ' from this wallet'}',
              ),
              if (goal > 0 && wallet != null)
                Text(
                  'The goal is shared across all wallets.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (savingsEntries.isNotEmpty) ...[
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'BY WALLET',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (wallet != null)
                      TextButton(
                        onPressed: withFeedback(
                          () => setState(() => wallet = null),
                        ),
                        child: const Text('All wallets'),
                      ),
                  ],
                ),
                for (final entry in savingsEntries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(entry.key),
                    subtitle: Text(
                      goal <= 0
                          ? 'Saved'
                          : '${math.min(100, (entry.value * 100 / goal).round())}% of the shared goal',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      money(entry.value, d.currency),
                      style: const TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 11,
                      ),
                    ),
                    onTap: withFeedback(
                      () => setState(
                        () => wallet = wallet == entry.key ? null : entry.key,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'Where it went',
                trailing: _scopeTag(c),
              ),
              if (categories.isEmpty)
                EmptyState(
                  'No spending this month.',
                  wallet == null
                      ? 'Expenses will show here by category.'
                      : 'No expenses assigned to $wallet this month.',
                  LucideIcons.chartPie,
                )
              else ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: Semantics(
                    label:
                        'Category spending total ${money(summary.expenses, d.currency)} for ${wallet ?? 'all wallets'}',
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
                            value: categories[i].value / summary.expenses,
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
          wallet == null ? 'Give your money a plan.' : 'Plan for $wallet.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scopeTag(c),
              IconButton(
                tooltip: wallet == null
                    ? 'Add planner rule'
                    : 'Add planner rule for $wallet',
                onPressed: withFeedback(
                  () => panel(c, RuleForm(data: d, initialMethod: wallet)),
                ),
                icon: const Icon(LucideIcons.plus),
              ),
            ],
          ),
        ),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: rules.isEmpty
              ? EmptyState(
                  wallet == null
                      ? 'A plan starts with one rule.'
                      : 'No rules for $wallet yet.',
                  wallet == null
                      ? 'Add payday savings, rent, or a daily allowance.'
                      : 'Add a rule to reserve money from this wallet.',
                  LucideIcons.calendarClock,
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: rules.length,
                  onReorderItem: (old, next) async {
                    final visible = [...rules];
                    visible.insert(next, visible.removeAt(old));
                    final full =
                        d.rules
                            .where((r) => r.currency == d.currency)
                            .toList()
                          ..sort((a, b) => a.position.compareTo(b.position));
                    final reordered = <Rule>[];
                    var index = 0;
                    for (final r in full) {
                      reordered.add(
                        wallet == null || walletMethodName(r.method) == wallet
                            ? visible[index++]
                            : r,
                      );
                    }
                    final db = ref.read(databaseProvider);
                    await guarded(
                      context,
                      () async {
                        await db.transaction(() async {
                          for (var i = 0; i < reordered.length; i++) {
                            await (db.update(db.rules)
                                  ..where((r) => r.id.equals(reordered[i].id)))
                                .write(RulesCompanion(position: Value(i)));
                          }
                        });
                      },
                      success: 'Planner rules reordered',
                      successIcon: DataAction.reordered.icon,
                    );
                  },
                  itemBuilder: (c, i) {
                    final r = rules[i];
                    return ListTile(
                      key: ValueKey(r.id),
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.title),
                      subtitle: Text(
                        '${r.cadence} · ${r.method} · ${r.basis == 'fixed' ? money(r.amount * r.quantity, d.currency) : '${editableMoney(r.amount, 'PHP')}% of ${r.basis} × ${r.quantity}'}',
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
        SectionHeading('Expected & actual', trailing: _scopeTag(c)),
        if (days.isEmpty)
          Surface(
            child: EmptyState(
              'A clean slate.',
              wallet == null
                  ? 'Add a transaction or a planner rule.'
                  : 'No activity for $wallet this month.',
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
        ),
        Positioned(
          top: 16,
          left: 72,
          right: 72,
          height: 48,
          child: IgnorePointer(
            ignoring: !_showCompactBalance,
            child: AnimatedSlide(
              offset: _showCompactBalance ? Offset.zero : const Offset(0, -0.2),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showCompactBalance ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff191b19), Color(0xff303630)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: .06)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'TOTAL BALANCE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .5),
                          fontSize: 7,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              masked
                                  ? walletMaskedAmount(d.currency)
                                  : money(totalBalance, d.currency),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Geist Mono',
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: masked ? 'Show amounts' : 'Hide amounts',
                        child: IconButton(
                          tooltip: masked ? 'Show amounts' : 'Hide amounts',
                          onPressed: withFeedback(_toggleMasked),
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white.withValues(alpha: .08),
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(
                            masked ? LucideIcons.eyeOff : LucideIcons.eye,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scopeTag(BuildContext c) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 120),
    child: Text(
      wallet ?? 'All wallets',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Theme.of(c).colorScheme.onSurfaceVariant,
      ),
    ),
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
          return PanelContent(
            header: PanelHeading(title: 'Savings goal'),
            footer: AppButton(
              label: 'Save goal',
              onPressed: () async {
                try {
                  final amount = parseMoney(field.text, widget.data.currency);
                  await ref
                      .read(databaseProvider)
                      .pref('savingsGoal:${widget.data.currency}', amount);
                  if (c.mounted) {
                    dataToast(c, 'Savings goal', DataAction.saved);
                    Navigator.pop(c);
                  }
                } catch (e) {
                  if (c.mounted) {
                    toast(
                      c,
                      e is FormatException
                          ? e.message
                          : 'Could not save goal. Try again.',
                      error: true,
                    );
                  }
                }
              },
            ),
            child: TextField(
              controller: field,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Goal · ${widget.data.currency}',
              ),
            ),
          );
        },
      ),
    );
    field.dispose();
  }
}
