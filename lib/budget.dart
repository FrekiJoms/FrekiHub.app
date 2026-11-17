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
  final GlobalKey _totalCardKey = GlobalKey();
  final ValueNotifier<double> _compactProgress = ValueNotifier<double>(0);
  double _cardTopAtOffset0 = 0;
  double _cardHeight = 0;
  bool _cardMetricsReady = false;
  late String _timelineSort; // date | amount | type
  late bool _timelineDesc;
  late bool _historyExpanded;
  late bool _monthCardExpanded;
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
    _historyExpanded = widget.data.prefs['financeHistoryExpanded'] != 'false';
    _timelineSort = widget.data.prefs['financeHistorySort'] ?? 'date';
    if (!const {'date', 'amount', 'type'}.contains(_timelineSort)) {
      _timelineSort = 'date';
    }
    _timelineDesc = widget.data.prefs['financeHistoryDesc'] == 'true';
    _monthCardExpanded =
        widget.data.prefs['financeMonthCardExpanded'] != 'false';
    _scrollController.addListener(_updateCompactProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCard());
  }

  @override
  void didUpdateWidget(covariant BudgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.prefs['walletMasked'] !=
        widget.data.prefs['walletMasked']) {
      masked = widget.data.prefs['walletMasked'] == 'true';
    }
    if (oldWidget.data.prefs['financeHistoryExpanded'] !=
        widget.data.prefs['financeHistoryExpanded']) {
      _historyExpanded = widget.data.prefs['financeHistoryExpanded'] != 'false';
    }
    if (oldWidget.data.prefs['financeHistorySort'] !=
        widget.data.prefs['financeHistorySort']) {
      final nextSort = widget.data.prefs['financeHistorySort'] ?? 'date';
      _timelineSort = const {'date', 'amount', 'type'}.contains(nextSort)
          ? nextSort
          : 'date';
    }
    if (oldWidget.data.prefs['financeHistoryDesc'] !=
        widget.data.prefs['financeHistoryDesc']) {
      _timelineDesc = widget.data.prefs['financeHistoryDesc'] == 'true';
    }
    if (oldWidget.data.prefs['financeMonthCardExpanded'] !=
        widget.data.prefs['financeMonthCardExpanded']) {
      _monthCardExpanded =
          widget.data.prefs['financeMonthCardExpanded'] != 'false';
    }
    if (wallet != null &&
        !widget.data.walletMethods.any(
          (w) => w.toLowerCase() == wallet!.toLowerCase(),
        )) {
      wallet = null;
    }
  }

  void _measureCard() {
    if (!mounted) return;
    final ctx = _totalCardKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    _cardTopAtOffset0 = top + offset;
    _cardHeight = box.size.height;
    _cardMetricsReady = _cardHeight > 0;
    _updateCompactProgress();
  }

  void _updateCompactProgress() {
    if (!mounted || !_scrollController.hasClients) return;
    if (!_cardMetricsReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureCard());
      return;
    }
    final topEdge = MediaQuery.of(context).padding.top;
    final top = _cardTopAtOffset0 - _scrollController.offset;
    final hidden = ((topEdge - top) / _cardHeight).clamp(0.0, 1.0);
    // Smoothly transform as the card becomes mostly hidden at the top (40% -> 75%).
    final progress = ((hidden - 0.4) / 0.35).clamp(0.0, 1.0);
    if ((progress - _compactProgress.value).abs() > 0.01 ||
        (progress == 0 && _compactProgress.value != 0) ||
        (progress == 1 && _compactProgress.value != 1)) {
      _compactProgress.value = progress;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _compactProgress.dispose();
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

  List<Rule> _scopedRules(AppData data) =>
      (wallet == null
              ? data.rules.where((r) => r.currency == data.currency)
              : data.rules.where(
                  (r) =>
                      r.currency == data.currency &&
                      walletMethodName(r.method) == wallet,
                ))
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final month = dayKey(period).substring(0, 7);
    final last = DateTime(period.year, period.month + 1, 0);
    final eligible = d.eligibleWalletKeys(wallet: wallet);
    final eligibleAll = d.eligibleWalletKeys();
    final plannedForPeriod = project(d, period, last);
    final planned = plannedForPeriod
        .where(
          (p) =>
              eligible.contains(walletMethodName(p.rule.method).toLowerCase()),
        )
        .toList();
    final summary = financeMonth(d, period, wallet, planned);
    final committed = walletCommitments(plannedForPeriod);
    final goal = int.tryParse(d.prefs['savingsGoal:${d.currency}'] ?? '') ?? 0;
    final saved = d
        .scopedEntries(wallet: wallet)
        .where((e) => e.kind == 'savings')
        .fold(0, (sum, e) => sum + e.amount);
    final savingsEntries = d.savingsByWallet.entries
        .where((e) => eligibleAll.contains(e.key.toLowerCase()))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final breakdown = <String, int>{};
    for (final e
        in d
            .scopedEntries(wallet: wallet, month: month)
            .where((e) => e.kind == 'expense')) {
      breakdown.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final categories = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final timelineRows = <_TimelineItem>[];
    final seenTransfers = <String>{};
    for (final e in d.scopedEntries(wallet: wallet, month: month)) {
      if (e.kind == 'transfer_out' || e.kind == 'transfer_in') {
        final pairKey =
            AppDatabase.transferPrefix(e.occurrence) ?? e.occurrence ?? e.id;
        if (wallet == null && !seenTransfers.add(pairKey)) continue;
        final from = e.kind == 'transfer_out' ? e.method : e.category;
        final to = e.kind == 'transfer_out' ? e.category : e.method;
        timelineRows.add(
          _TimelineItem(
            day: e.day,
            title: e.note.isEmpty
                ? (wallet == null
                      ? '$from → $to'
                      : (e.kind == 'transfer_out'
                            ? 'Transfer to $to'
                            : 'Transfer from $from'))
                : e.note,
            detail: 'Transfer · $from → $to',
            amount: e.amount,
            kind: wallet == null ? 'transfer' : e.kind,
            planned: false,
            status: 'actual',
            onTap: () => panel(
              c,
              e.occurrence != null
                  ? WalletTransferSheet(
                      data: d,
                      existingOccurrence: e.occurrence,
                    )
                  : EntryForm(data: d, day: e.day, kind: 'expense', entry: e),
            ),
          ),
        );
        continue;
      }
      timelineRows.add(
        _TimelineItem(
          day: e.day,
          title: e.note.isEmpty ? e.category : e.note,
          detail: 'Actual · ${e.category} · ${e.method}',
          amount: e.amount,
          kind: e.kind,
          planned: false,
          status: 'actual',
          onTap: () =>
              panel(c, EntryForm(data: d, day: e.day, kind: e.kind, entry: e)),
        ),
      );
    }
    for (final p in planned) {
      if (p.status == 'complete') continue;
      timelineRows.add(
        _TimelineItem(
          day: p.day,
          title: p.rule.title,
          detail:
              'Expected · ${p.status} · ${p.rule.category} · ${p.rule.method}',
          amount: p.amount,
          kind: p.rule.kind,
          planned: true,
          status: p.status,
          error: p.error,
          onTap: () => occurrence(p),
        ),
      );
    }
    int typeRank(_TimelineItem it) {
      if (it.planned) return 0;
      if (it.kind == 'income') return 1;
      if (it.kind == 'savings') return 2;
      return 3; // expense/other
    }

    timelineRows.sort((a, b) {
      int cmp;
      switch (_timelineSort) {
        case 'amount':
          cmp = a.amount.compareTo(b.amount);
          if (cmp == 0) cmp = a.day.compareTo(b.day);
          if (cmp == 0) cmp = typeRank(a).compareTo(typeRank(b));
          break;
        case 'type':
          cmp = typeRank(a).compareTo(typeRank(b));
          if (cmp == 0) cmp = a.day.compareTo(b.day);
          if (cmp == 0) cmp = a.amount.compareTo(b.amount);
          break;
        case 'date':
        default:
          cmp = a.day.compareTo(b.day);
          if (cmp == 0) cmp = typeRank(a).compareTo(typeRank(b));
          if (cmp == 0) cmp = a.title.compareTo(b.title);
      }
      return _timelineDesc ? -cmp : cmp;
    });
    final accounts = walletAccounts(d, null, committed);
    final totalBalance = summary.available;
    return Stack(
      children: [
        PageBody(
          scrollController: _scrollController,
          children: [
            const SizedBox(height: 72),
            WalletSection(
              data: d,
              accounts: accounts,
              month: summary,
              wallet: wallet,
              committed: committed,
              maskedOverride: masked,
              onToggleMasked: _toggleMasked,
              totalCardKey: _totalCardKey,
              monthCardExpanded: _monthCardExpanded,
              onMonthCardExpandedChanged: (expanded) {
                setState(() => _monthCardExpanded = expanded);
                unawaited(
                  ref
                      .read(databaseProvider)
                      .pref('financeMonthCardExpanded', '$expanded')
                      .catchError((Object _) {}),
                );
              },
              onPeriod: (next) =>
                  setState(() => period = DateTime(next.year, next.month)),
              onWallet: (name) => setState(() => wallet = name),
              belowMonthCard: Chrome(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Expanded(
                      child: _CompactPillButton(
                        label: 'Plan',
                        icon: LucideIcons.calendarClock,
                        onTap: () => panel(
                          c,
                          Consumer(
                            builder: (c, ref, _) {
                              final live = ref.watch(dataProvider).value ?? d;
                              final rules = _scopedRules(live);
                              return PanelContent(
                                header: PanelHeading(
                                  title: wallet == null
                                      ? 'Plan'
                                      : 'Plan · $wallet',
                                  trailing: IconButton(
                                    tooltip: wallet == null
                                        ? 'Add planner rule'
                                        : 'Add planner rule for $wallet',
                                    onPressed: withFeedback(
                                      () => panel(
                                        c,
                                        RuleForm(
                                          data: live,
                                          initialMethod: wallet,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(LucideIcons.plus),
                                  ),
                                ),
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
                                    : Column(
                                        children: [
                                          for (final r in rules)
                                            ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(r.title),
                                              subtitle: Text(
                                                '${r.cadence} · ${r.method} · ${r.basis == 'fixed' ? money(r.amount * r.quantity, live.currency) : '${editableMoney(r.amount, 'PHP')}% of ${r.basis} × ${r.quantity}'}',
                                              ),
                                              onTap: withFeedback(
                                                () => ruleMenu(r),
                                              ),
                                            ),
                                        ],
                                      ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactPillButton(
                        label: 'Analytics',
                        icon: LucideIcons.chartPie,
                        onTap: () => panel(
                          c,
                          PanelContent(
                            header: PanelHeading(
                              title: 'Analytics',
                              trailing: _scopeTag(c),
                            ),
                            child: categories.isEmpty
                                ? EmptyState(
                                    'No spending this month.',
                                    wallet == null
                                        ? 'Expenses will show here by category.'
                                        : 'No expenses assigned to $wallet this month.',
                                    LucideIcons.chartPie,
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 180,
                                        child: Semantics(
                                          label:
                                              'Category spending total ${money(summary.expenses, d.currency)} for ${wallet ?? 'all wallets'}',
                                          child: PieChart(
                                            PieChartData(
                                              centerSpaceRadius: 48,
                                              sectionsSpace: 4,
                                              sections: List.generate(
                                                categories.length,
                                                (i) => PieChartSectionData(
                                                  value: categories[i].value
                                                      .toDouble(),
                                                  color:
                                                      Design.chart[i %
                                                          Design.chart.length],
                                                  radius: 26,
                                                  showTitle: false,
                                                ),
                                              ),
                                              pieTouchData: PieTouchData(
                                                enabled: true,
                                              ),
                                            ),
                                            duration: Motion.duration(c),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ...List.generate(
                                        categories.length,
                                        (i) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Design.chart[i %
                                                              Design
                                                                  .chart
                                                                  .length],
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      categories[i].key,
                                                    ),
                                                  ),
                                                  Text(
                                                    money(
                                                      categories[i].value,
                                                      d.currency,
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily: 'Geist Mono',
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: LinearProgressIndicator(
                                                  value: summary.expenses <= 0
                                                      ? 0
                                                      : categories[i].value /
                                                            summary.expenses,
                                                  minHeight: 4,
                                                  color:
                                                      Design.chart[i %
                                                          Design.chart.length],
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
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactPillButton(
                        label: 'Savings',
                        icon: LucideIcons.piggyBank,
                        onTap: () => panel(
                          c,
                          PanelContent(
                            header: PanelHeading(
                              title: 'Savings',
                              trailing: IconButton(
                                tooltip: 'Set savings goal',
                                onPressed: withFeedback(() => savingsGoal(c)),
                                icon: const Icon(
                                  LucideIcons.pencilLine,
                                  size: 18,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  wallet == null
                                      ? 'SAVED · ALL WALLETS'
                                      : 'SAVED · ${wallet!.toUpperCase()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                NumberValue(money(saved, d.currency), size: 28),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: goal <= 0
                                        ? 0
                                        : (saved / goal).clamp(0, 1),
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
                                      color: Theme.of(c)
                                          .colorScheme
                                          .onSurfaceVariant,
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
                                            color: Theme.of(c)
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                          () => wallet = wallet == entry.key
                                              ? null
                                              : entry.key,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SectionHeading(
              'History',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _scopeTag(c),
                  if (_historyExpanded) ...[
                    const SizedBox(width: 4),
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Sort',
                        visualDensity: VisualDensity.compact,
                        onPressed: withFeedback(() async {
                          final current =
                              '${_timelineSort}_${_timelineDesc ? 'desc' : 'asc'}';
                          final value = await showChoiceMenu<String>(
                            anchor,
                            choices: const {
                              'date_asc': 'Date (oldest first)',
                              'date_desc': 'Date (newest first)',
                              'amount_asc': 'Amount (low to high)',
                              'amount_desc': 'Amount (high to low)',
                              'type_asc': 'Type',
                              'type_desc': 'Type (reverse)',
                            },
                            selected: current,
                          );
                          if (value == null) return;
                          final parts = value.split('_');
                          setState(() {
                            _timelineSort = parts[0];
                            _timelineDesc = parts[1] == 'desc';
                          });
                          final db = ref.read(databaseProvider);
                          unawaited(
                            db
                                .pref('financeHistorySort', _timelineSort)
                                .catchError((Object _) {}),
                          );
                          unawaited(
                            db
                                .pref('financeHistoryDesc', '$_timelineDesc')
                                .catchError((Object _) {}),
                          );
                        }),
                        icon: Icon(
                          _timelineDesc
                              ? LucideIcons.arrowDownWideNarrow
                              : LucideIcons.arrowUpNarrowWide,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: _historyExpanded ? 'Minimize' : 'Expand',
                    visualDensity: VisualDensity.compact,
                    onPressed: withFeedback(() {
                      setState(() => _historyExpanded = !_historyExpanded);
                      unawaited(
                        ref
                            .read(databaseProvider)
                            .pref('financeHistoryExpanded', '$_historyExpanded')
                            .catchError((Object _) {}),
                      );
                    }),
                    icon: Icon(
                      _historyExpanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            if (_historyExpanded)
              (timelineRows.isEmpty
                  ? Surface(
                      child: EmptyState(
                        'A clean slate.',
                        wallet == null
                            ? 'Add a transaction or a planner rule.'
                            : 'No activity for $wallet this month.',
                        LucideIcons.wallet,
                      ),
                    )
                  : Surface(
                      child: Column(
                        children: [
                          for (var i = 0; i < timelineRows.length; i++) ...[
                            _TimelineRow(
                              item: timelineRows[i],
                              currency: d.currency,
                              showDay: true,
                            ),
                            if (i != timelineRows.length - 1)
                              Divider(
                                height: 1,
                                color: Theme.of(c).colorScheme.outlineVariant
                                    .withValues(alpha: .4),
                              ),
                          ],
                        ],
                      ),
                    )),
          ],
        ),
        Positioned(
          top: 16,
          left: 72,
          right: 72,
          height: 48,
          child: ValueListenableBuilder<double>(
            valueListenable: _compactProgress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  wallet == null ? 'AVAILABLE' : wallet!.toUpperCase(),
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
            builder: (context, progress, child) {
              final reduce =
                  MediaQuery.maybeOf(context)?.disableAnimations ?? false;
              final t = reduce ? (progress >= 0.5 ? 1.0 : 0.0) : progress;
              final curved = Curves.easeOutCubic.transform(t);
              return IgnorePointer(
                ignoring: t <= 0.01,
                child: Opacity(
                  opacity: curved,
                  child: Transform.translate(
                    offset: Offset(0, (1 - curved) * -8),
                    child: Transform.scale(
                      scale: 0.97 + (0.03 * curved),
                      alignment: Alignment.topCenter,
                      child: RepaintBoundary(
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
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: 0.16 * curved,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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

class _TimelineItem {
  final String day;
  final String title;
  final String detail;
  final int amount;
  final String kind;
  final bool planned;
  final String status;
  final String? error;
  final VoidCallback onTap;
  const _TimelineItem({
    required this.day,
    required this.title,
    required this.detail,
    required this.amount,
    required this.kind,
    required this.planned,
    required this.status,
    required this.onTap,
    this.error,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final String currency;
  final bool showDay;
  const _TimelineRow({
    required this.item,
    required this.currency,
    this.showDay = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = item.kind == 'income' || item.kind == 'transfer_in';
    final isExpense = item.kind == 'expense' || item.kind == 'transfer_out';
    final isSavings = item.kind == 'savings';
    final isTransfer = item.kind == 'transfer';
    final Color amountColor;
    final String sign;
    if (isTransfer) {
      amountColor = scheme.onSurfaceVariant;
      sign = '';
    } else if (isIncome) {
      amountColor = const Color(0xFF2E7D32);
      sign = '+';
    } else if (isExpense) {
      amountColor = const Color(0xFFC62828);
      sign = '−';
    } else if (isSavings) {
      amountColor = const Color(0xFF2E7D32);
      sign = '−';
    } else {
      amountColor = scheme.onSurface;
      sign = '';
    }
    final amountText = item.error != null
        ? 'Needs review'
        : '$sign${money(item.amount, currency)}';
    return InkWell(
      onTap: withFeedback(item.onTap),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (item.planned)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E88E5),
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    showDay ? '${item.day} · ${item.detail}' : item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: item.error != null
                    ? scheme.onSurfaceVariant
                    : amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _CompactPillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: withFeedback(onTap),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
