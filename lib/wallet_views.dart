part of 'screens.dart';

class WalletSection extends ConsumerStatefulWidget {
  final AppData data;

  /// Selected month summary rendered between the total and the cards.
  final FinanceMonth? month;

  /// Wallet currently scoping the rest of Finance, or null for all wallets.
  final String? wallet;
  final ValueChanged<DateTime>? onPeriod;
  final ValueChanged<String?>? onWallet;

  /// Planned outflows for the selected month, keyed by wallet.
  final Map<String, int> committed;
  final List<WalletAccount>? accounts;
  final bool? maskedOverride;
  final GlobalKey? totalCardKey;
  final VoidCallback? onToggleMasked;
  final Widget? belowMonthCard;
  final bool? monthCardExpanded;
  final ValueChanged<bool>? onMonthCardExpandedChanged;
  const WalletSection({
    super.key,
    required this.data,
    this.month,
    this.wallet,
    this.onPeriod,
    this.onWallet,
    this.committed = const {},
    this.accounts,
    this.maskedOverride,
    this.totalCardKey,
    this.onToggleMasked,
    this.belowMonthCard,
    this.monthCardExpanded,
    this.onMonthCardExpandedChanged,
  });
  @override
  ConsumerState<WalletSection> createState() => _WalletSectionState();
}

class _WalletSectionState extends ConsumerState<WalletSection> {
  late WalletView view;
  late bool masked;
  late List<String> order;

  @override
  void initState() {
    super.initState();
    view = WalletView.restore(widget.data.prefs['walletView']);
    masked =
        widget.maskedOverride ?? (widget.data.prefs['walletMasked'] == 'true');
    order = widget.data.orderedWalletNames(
      walletStoredOrder(widget.data.prefs),
    );
  }

  @override
  void didUpdateWidget(covariant WalletSection old) {
    super.didUpdateWidget(old);
    final next = widget.data.orderedWalletNames(
      old.data.prefs['walletOrder'] != widget.data.prefs['walletOrder']
          ? walletStoredOrder(widget.data.prefs)
          : order,
    );
    if (!_sameNames(next, order)) order = next;
    if (widget.maskedOverride != null) {
      masked = widget.maskedOverride!;
    } else if (old.data.prefs['walletMasked'] !=
        widget.data.prefs['walletMasked']) {
      masked = widget.data.prefs['walletMasked'] == 'true';
    }
    if (old.data.prefs['walletView'] != widget.data.prefs['walletView']) {
      view = WalletView.restore(widget.data.prefs['walletView']);
    }
  }

  List<WalletAccount> _accounts() {
    final provided = widget.accounts;
    if (provided != null &&
        _sameNames(provided.map((a) => a.name).toList(), order)) {
      return provided;
    }
    return walletAccounts(
      widget.data,
      widget.data.orderedWalletNames(order),
      widget.committed,
    );
  }

  Future<void> _scope([List<WalletAccount>? current]) async {
    final accounts = current ?? _accounts();
    await panel(
      context,
      _WalletScopeSheet(
        accounts: accounts,
        selected: widget.wallet,
        currency: widget.data.currency,
        onPick: (name) {
          Navigator.pop(context);
          widget.onWallet?.call(name);
        },
      ),
    );
  }

  void _focus(WalletAccount account) {
    widget.onWallet?.call(account.name);
    dataToast(context, 'Finance scoped to ${account.name}', DataAction.updated);
  }

  Future<bool> _saveOrder(List<String> names) async {
    try {
      await ref.read(databaseProvider).pref('walletOrder', jsonEncode(names));
      return true;
    } catch (_) {
      if (mounted) {
        toast(context, 'Could not save card order. Try again.', error: true);
      }
      return false;
    }
  }

  Future<bool> _move(WalletAccount account, {required bool toBack}) async {
    final previous = _accounts().map((a) => a.name).toList();
    final names = [...previous];
    names.remove(account.name);
    if (toBack) {
      names.add(account.name);
    } else {
      names.insert(0, account.name);
    }
    setState(() => order = names);
    HapticFeedback.selectionClick();
    if (await _saveOrder(names)) return true;
    if (mounted) setState(() => order = previous);
    return false;
  }

  Future<void> _moveToFront(WalletAccount account) async {
    if (await _move(account, toBack: false) && mounted) {
      dataToast(context, 'Wallet', DataAction.reordered);
    }
  }

  Future<void> _setIncluded(WalletAccount account, bool included) async {
    try {
      await ref
          .read(databaseProvider)
          .pref('wallet:${account.name}:include', '$included');
      if (mounted) dataToast(context, 'Wallet', DataAction.updated);
    } catch (_) {
      if (mounted) {
        toast(context, 'Could not update this wallet. Try again.', error: true);
      }
    }
  }

  void _setView(WalletView next) {
    if (view == next) return;
    HapticFeedback.selectionClick();
    setState(() => view = next);
    unawaited(
      ref
          .read(databaseProvider)
          .pref('walletView', next.id)
          .catchError((Object _) {}),
    );
  }

  bool get _effectiveMasked => widget.maskedOverride ?? masked;

  void _toggleMasked() {
    final external = widget.onToggleMasked;
    if (external != null) {
      external();
      return;
    }
    setState(() => masked = !masked);
    unawaited(
      ref
          .read(databaseProvider)
          .pref('walletMasked', '$masked')
          .catchError((Object _) {}),
    );
  }

  Future<void> _detail(WalletAccount account) {
    final entries = widget.data.walletEntries(account.name)
      ..sort((a, b) {
        final byDay = b.day.compareTo(a.day);
        return byDay != 0 ? byDay : b.amount.compareTo(a.amount);
      });
    return panel(
      context,
      Builder(
        builder: (sheet) => _WalletDetail(
          account: account,
          entries: entries,
          currency: widget.data.currency,
          masked: _effectiveMasked,
          selected: widget.wallet == account.name,
          onEdit: () {
            Navigator.pop(sheet);
            _design(account);
          },
          onFront: () {
            Navigator.pop(sheet);
            _moveToFront(account);
          },
          onFocus: widget.onWallet == null
              ? null
              : () {
                  Navigator.pop(sheet);
                  _focus(account);
                },
        ),
      ),
    );
  }

  Future<void> _menu(WalletAccount account) => panel(
    context,
    Builder(
      builder: (sheet) => _WalletMenu(
        account: account,
        selected: widget.wallet == account.name,
        onEdit: () {
          Navigator.pop(sheet);
          _design(account);
        },
        onFront: () {
          Navigator.pop(sheet);
          _moveToFront(account);
        },
        onIncluded: (value) {
          Navigator.pop(sheet);
          _setIncluded(account, value);
        },
        onAdd: () {
          Navigator.pop(sheet);
          _addWallet();
        },
        onFocus: widget.onWallet == null
            ? null
            : () {
                Navigator.pop(sheet);
                _focus(account);
              },
      ),
    ),
  );

  Future<void> _design(WalletAccount account) =>
      panel(context, _WalletDesignSheet(account: account, data: widget.data));

  Future<void> _addWallet() =>
      panel(context, _AddWalletSheet(data: widget.data));

  @override
  Widget build(BuildContext c) {
    final accounts = _accounts();
    final included = accounts.where((a) => a.included).toList();
    final total = included.fold(0, (sum, a) => sum + a.balance);
    final assets = included
        .where((a) => a.balance > 0)
        .fold(0, (sum, a) => sum + a.balance);
    final liabilities = included
        .where((a) => a.balance < 0)
        .fold(0, (sum, a) => sum - a.balance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: widget.totalCardKey,
          child: _WalletTotalCard(
            total: total,
            assets: assets,
            liabilities: liabilities,
            count: included.length,
            currency: widget.data.currency,
            masked: _effectiveMasked,
            onToggle: _toggleMasked,
          ),
        ),
        if (widget.month != null) ...[
          const SizedBox(height: 10),
          _WalletMonthCard(
            month: widget.month!,
            wallet: widget.wallet,
            wallets: accounts.map((a) => a.name).toList(),
            currency: widget.data.currency,
            masked: _effectiveMasked,
            expanded: widget.monthCardExpanded,
            onExpandedChanged: widget.onMonthCardExpandedChanged,
            onPeriod: widget.onPeriod,
            onScope: widget.onWallet == null ? null : () => _scope(accounts),
          ),
        ],
        if (widget.belowMonthCard != null) ...[
          const SizedBox(height: 10),
          widget.belowMonthCard!,
        ],
        const SizedBox(height: 10),
        _WalletToolbar(
          count: accounts.length,
          view: view,
          onView: _setView,
          onAdd: _addWallet,
        ),
        const SizedBox(height: 10),
        if (accounts.isEmpty)
          const Surface(
            child: EmptyState(
              'No wallets yet.',
              'Add a payment method to separate your money.',
              LucideIcons.wallet,
            ),
          )
        else
          switch (view) {
            WalletView.rows => _WalletRows(
              accounts: accounts,
              currency: widget.data.currency,
              masked: _effectiveMasked,
              selected: widget.wallet,
              onOpen: _detail,
              onReorder: (names) async {
                final previous = List<String>.from(order);
                setState(() => order = names);
                if (!await _saveOrder(names) && mounted) {
                  setState(() => order = previous);
                }
              },
            ),
            WalletView.grid => _WalletGrid(
              accounts: accounts,
              currency: widget.data.currency,
              masked: _effectiveMasked,
              selected: widget.wallet,
              onOpen: _detail,
              onMenu: _menu,
            ),
            WalletView.stack => _WalletDeck(
              key: ValueKey(accounts.map((a) => a.name).join('|')),
              accounts: accounts,
              currency: widget.data.currency,
              masked: _effectiveMasked,
              selected: widget.wallet,
              onOpen: _detail,
              onMenu: _menu,
              onNext: (account) => _move(account, toBack: true),
              onPrevious: (account) => _move(account, toBack: false),
            ),
          },
      ],
    );
  }
}

bool _sameNames(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _WalletTotalCard extends StatelessWidget {
  final int total, assets, liabilities, count;
  final String currency;
  final bool masked;
  final VoidCallback onToggle;
  const _WalletTotalCard({
    required this.total,
    required this.assets,
    required this.liabilities,
    required this.count,
    required this.currency,
    required this.masked,
    required this.onToggle,
  });

  String _short(int amount) =>
      masked ? walletMaskedAmount(currency) : money(amount, currency);

  @override
  Widget build(BuildContext c) {
    final title = masked
        ? 'Total net balance, amounts hidden'
        : 'Total net balance ${money(total, currency)}';
    return Semantics(
      container: true,
      label: '$title, across $count wallets',
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
                    'TOTAL BALANCE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 10,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: masked ? 'Show amounts' : 'Hide amounts',
                  child: IconButton(
                    tooltip: masked ? 'Show amounts' : 'Hide amounts',
                    onPressed: onToggle,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      maximumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      masked ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                    ),
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
                      masked
                          ? walletMaskedAmount(currency)
                          : money(total, currency),
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
                const SizedBox(width: 12),
                Text(
                  '$count ${count == 1 ? 'wallet' : 'wallets'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .55),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'All wallets · all time, in $currency',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .5),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TotalMetric(label: 'Assets', value: _short(assets)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TotalMetric(
                    label: 'Owed',
                    value: _short(liabilities),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TotalMetric(
                    label: 'Wallets',
                    value: '$count',
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

class _TotalMetric extends StatelessWidget {
  final String label, value;
  final bool numeric;
  const _TotalMetric({
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WalletMonthCard extends StatefulWidget {
  final FinanceMonth month;
  final String? wallet;
  final List<String> wallets;
  final String currency;
  final bool masked;
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<DateTime>? onPeriod;
  final VoidCallback? onScope;
  const _WalletMonthCard({
    required this.month,
    required this.wallet,
    required this.wallets,
    required this.currency,
    required this.masked,
    this.expanded,
    this.onExpandedChanged,
    required this.onPeriod,
    required this.onScope,
  });

  @override
  State<_WalletMonthCard> createState() => _WalletMonthCardState();
}

class _WalletMonthCardState extends State<_WalletMonthCard> {
  late bool _expanded = widget.expanded ?? true;

  @override
  void didUpdateWidget(covariant _WalletMonthCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != null && widget.expanded != _expanded) {
      _expanded = widget.expanded!;
    }
  }

  String get scope => widget.wallet ?? 'All wallets';

  @override
  Widget build(BuildContext c) {
    final expanded = widget.expanded ?? _expanded;
    final month = widget.month;
    final period = month.period;
    final last = DateTime(period.year, period.month + 1, 0);
    final amount = widget.masked
        ? walletMaskedAmount(widget.currency)
        : money(month.net, widget.currency);
    final safe = widget.masked
        ? walletMaskedAmount(widget.currency)
        : money(month.safe, widget.currency);
    final theme = Theme.of(c);
    return Surface(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: widget.onPeriod == null
                    ? null
                    : withFeedback(
                        () => widget.onPeriod!(
                          DateTime(period.year, period.month - 1),
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
                onPressed: widget.onPeriod == null
                    ? null
                    : withFeedback(
                        () => widget.onPeriod!(
                          DateTime(period.year, period.month + 1),
                        ),
                      ),
                icon: const Icon(LucideIcons.chevronRight),
              ),
              IconButton(
                tooltip: expanded ? 'Minimize month card' : 'Expand month card',
                onPressed: withFeedback(() {
                  final next = !expanded;
                  if (widget.onExpandedChanged != null) {
                    widget.onExpandedChanged!(next);
                  } else {
                    setState(() => _expanded = next);
                  }
                }),
                icon: Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                ),
              ),
            ],
          ),
          if (!expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Month net · $scope',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    amount,
                    style: const TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MONTH NET · ${scope.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                amount,
                                style: const TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 30,
                                  height: 1.05,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Semantics(
                        label:
                            '${(month.used * 100).round()} percent of the month elapsed',
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: month.used,
                                  strokeWidth: 4,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                              Text(
                                '${(month.used * 100).round()}%',
                                style: const TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${DateFormat('MMM').format(period)} · ${last.day} days · ${(month.used * 100).round()}% of period elapsed',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: widget.onScope != null,
                      label: 'Finance scope, currently $scope',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.onScope,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 230),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.wallet, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  scope,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                LucideIcons.chevronDown,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  const Text(
                    'Safe to spend',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      safe,
                      style: const TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    month.commitments == 0
                        ? 'No remaining planned expenses or savings for $scope in ${DateFormat('MMMM').format(period)}.'
                        : 'After ${money(month.commitments, widget.currency)} in remaining planned expenses and savings for $scope.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
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
                            ('Income', month.income),
                            ('Spent', month.expenses),
                            ('Saved', month.savings),
                          ])
                            SizedBox(
                              width: width,
                              child: _MonthMetric(
                                label: value.$1,
                                value: widget.masked
                                    ? walletMaskedAmount(widget.currency)
                                    : money(value.$2, widget.currency),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  if (widget.wallets.length > 1 && widget.onScope != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.wallet == null
                          ? 'Tap the scope chip to read one wallet only. Cards below stay separate.'
                          : 'Charts, planner and timeline below follow $scope. Tap a card to open it.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthMetric extends StatelessWidget {
  final String label, value;
  const _MonthMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext c) => Column(
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
}

class _WalletScopeSheet extends StatelessWidget {
  final List<WalletAccount> accounts;
  final String? selected;
  final String currency;
  final ValueChanged<String?> onPick;
  const _WalletScopeSheet({
    required this.accounts,
    required this.selected,
    required this.currency,
    required this.onPick,
  });

  @override
  Widget build(BuildContext c) => PanelContent(
    header: const PanelHeading(title: 'Finance scope'),
    footer: AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose the wallet used by month totals, safe to spend, the category chart, planner and timeline.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(c).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.wallet, size: 22),
          title: const Text('All wallets'),
          subtitle: const Text(
            'The whole ledger, as before.',
            style: TextStyle(fontSize: 11),
          ),
          trailing: selected == null
              ? const Icon(LucideIcons.check, size: 18)
              : null,
          onTap: () => onPick(null),
        ),
        const Divider(),
        for (final account in accounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _WalletMark(account: account, size: 34),
            title: Text(account.name),
            subtitle: Text(
              'Balance ${money(account.balance, currency)}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: selected == account.name
                ? const Icon(LucideIcons.check, size: 18)
                : null,
            onTap: () => onPick(account.name),
          ),
      ],
    ),
  );
}

class _WalletToolbar extends StatelessWidget {
  final int count;
  final WalletView view;
  final ValueChanged<WalletView> onView;
  final VoidCallback onAdd;
  const _WalletToolbar({
    required this.count,
    required this.view,
    required this.onView,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    return Row(
      children: [
        Expanded(
          child: Text(
            count <= 1
                ? 'Add another wallet to separate your money.'
                : 'Hold to rearrange · tap a card to open it.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in WalletView.values)
                Tooltip(
                  message: '${option.label} wallet view',
                  child: Semantics(
                    button: true,
                    selected: option == view,
                    label: '${option.label} wallet view',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onView(option),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: option == view
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: .1,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          option.icon,
                          size: 15,
                          color: option == view
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Add wallet',
          onPressed: onAdd,
          style: IconButton.styleFrom(
            minimumSize: const Size(38, 38),
            maximumSize: const Size(38, 38),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(LucideIcons.plus, size: 18),
        ),
      ],
    );
  }
}

class _WalletRows extends StatelessWidget {
  final List<WalletAccount> accounts;
  final String currency;
  final bool masked;
  final String? selected;
  final ValueChanged<WalletAccount> onOpen;
  final ValueChanged<List<String>> onReorder;
  const _WalletRows({
    required this.accounts,
    required this.currency,
    required this.masked,
    required this.selected,
    required this.onOpen,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext c) {
    _WalletAppIcons.prefetch(accounts.map((a) => a.name));
    return Surface(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: accounts.length,
      onReorderItem: (old, next) {
        final names = accounts.map((a) => a.name).toList();
        names.insert(next, names.removeAt(old));
        onReorder(names);
      },
      itemBuilder: (c, i) {
        final account = accounts[i];
        return Column(
          key: ValueKey(account.name),
          children: [
            ReorderableDelayedDragStartListener(
              index: i,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: _WalletMark(account: account, size: 38),
                title: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  account.name == selected
                      ? 'Scoping Finance to this wallet'
                      : account.committed > 0
                      ? '${account.included ? 'Included' : 'Excluded'} · ${masked ? 'planned' : '${money(account.committed, currency)} planned'}'
                      : account.included
                      ? 'Included in total'
                      : 'Excluded from total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => onOpen(account),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (account.name == selected) ...[
                      Icon(
                        LucideIcons.check,
                        size: 15,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      masked
                          ? walletMaskedAmount(currency)
                          : money(account.balance, currency),
                      style: TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 12,
                        color: account.balance < 0
                            ? Theme.of(c).colorScheme.error
                            : Theme.of(c).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      LucideIcons.gripVertical,
                      size: 16,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (i < accounts.length - 1)
              Divider(
                height: 1,
                indent: 54,
                endIndent: 8,
                color: Theme.of(c).colorScheme.outlineVariant
                    .withValues(alpha: .5),
              ),
          ],
        );
      },
    ),
  );
  }
}

class _WalletGrid extends StatelessWidget {
  final List<WalletAccount> accounts;
  final String currency;
  final bool masked;
  final String? selected;
  final ValueChanged<WalletAccount> onOpen;
  final ValueChanged<WalletAccount> onMenu;
  const _WalletGrid({
    required this.accounts,
    required this.currency,
    required this.masked,
    required this.selected,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, constraints) {
      final columns = constraints.maxWidth >= 560 ? 3 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final account in accounts)
            SizedBox(
              width: width,
              child: WalletCard(
                account: account,
                currency: currency,
                masked: masked,
                compact: true,
                selected: account.name == selected,
                onTap: () => onOpen(account),
                onLongPress: () => onMenu(account),
                onMenu: () => onMenu(account),
                semanticsLabel:
                    '${account.name} wallet, ${masked ? 'amount hidden' : money(account.balance, currency)}. ${account.committed > 0 ? (masked ? 'Has planned outflows. ' : '${money(account.committed, currency)} planned. ') : ''}${account.included ? 'Included in total' : 'Excluded from total'}.',
              ),
            ),
        ],
      );
    },
  );
}

class _WalletDeck extends StatefulWidget {
  final List<WalletAccount> accounts;
  final String currency;
  final bool masked;
  final String? selected;
  final ValueChanged<WalletAccount> onOpen;
  final ValueChanged<WalletAccount> onMenu;
  final ValueChanged<WalletAccount> onNext;
  final ValueChanged<WalletAccount> onPrevious;
  const _WalletDeck({
    super.key,
    required this.accounts,
    required this.currency,
    required this.masked,
    required this.selected,
    required this.onOpen,
    required this.onMenu,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<_WalletDeck> createState() => _WalletDeckState();
}

class _WalletDeckState extends State<_WalletDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Offset drag = Offset.zero, from = Offset.zero, to = Offset.zero;
  VoidCallback? finish;

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  Offset get current {
    if (!motion.isAnimating) return drag;
    final t = Curves.easeOut.transform(motion.value);
    return Offset.lerp(from, to, t) ?? drag;
  }

  void _animateTo(Offset target, int milliseconds, [VoidCallback? done]) {
    from = current;
    to = target;
    finish = done;
    motion.duration = Motion.duration(context, milliseconds);
    motion.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      final callback = finish;
      finish = null;
      setState(() {
        drag = Offset.zero;
        from = Offset.zero;
        to = Offset.zero;
        motion.reset();
      });
      callback?.call();
    });
  }

  void _release(Offset velocity, double width, double height) {
    if (motion.isAnimating) return;
    if (widget.accounts.length < 2) {
      _animateTo(Offset.zero, 220);
      return;
    }
    final speed = velocity.distance;
    final far = drag.distance > width * .16 || speed > 620;
    if (!far) {
      _animateTo(Offset.zero, 220);
      return;
    }
    final direction = drag.distance > 12
        ? drag / drag.distance
        : speed > 0
        ? velocity / speed
        : const Offset(0, -1);
    final distance = math.max(width, height) * 1.4;
    final duration = (310 - speed / 20).clamp(170, 320).round();
    _animateTo(direction * distance, duration, () {
      if (mounted) widget.onNext(widget.accounts.first);
    });
  }

  @override
  Widget build(BuildContext c) {
    final accounts = widget.accounts;
    if (accounts.isEmpty) return const SizedBox.shrink();
    final front = accounts.first;
    return LayoutBuilder(
      builder: (c, constraints) {
        final width = constraints.maxWidth;
        final height = width / 1.586;
        final behind = math.min(3, accounts.length - 1);
        return Column(
          children: [
            SizedBox(
              height: height + 30,
              child: AnimatedBuilder(
                animation: motion,
                builder: (c, _) {
                  final offset = current;
                  final angle = (offset.dx / width).clamp(-1.2, 1.2) * .2;
                  final scale =
                      (1 - math.min(.05, offset.distance / width * .05))
                          .toDouble();
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      for (var i = behind; i >= 1; i--)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Transform.translate(
                            offset: Offset(0, 7.0 * i),
                            child: Transform.scale(
                              scale: 1 - .04 * i,
                              alignment: Alignment.topCenter,
                              child: Opacity(
                                opacity: 1 - .14 * i,
                                child: WalletCard(
                                  account: accounts[i % accounts.length],
                                  currency: widget.currency,
                                  masked: widget.masked,
                                  selected:
                                      accounts[i % accounts.length].name ==
                                      widget.selected,
                                  showMenu: false,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Semantics(
                          label:
                              '${front.name} wallet, ${widget.masked ? 'amount hidden' : money(front.balance, widget.currency)}, card 1 of ${accounts.length}',
                          onIncrease: () => widget.onNext(front),
                          onDecrease: () => widget.onPrevious(accounts.last),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: motion.isAnimating
                                ? null
                                : () => widget.onOpen(front),
                            onPanStart: motion.isAnimating
                                ? null
                                : (_) {
                                    setState(() => drag = Offset.zero);
                                  },
                            onPanUpdate: motion.isAnimating
                                ? null
                                : (details) {
                                    setState(() => drag += details.delta);
                                  },
                            onPanEnd: motion.isAnimating
                                ? null
                                : (details) => _release(
                                    details.velocity.pixelsPerSecond,
                                    width,
                                    height,
                                  ),
                            child: Transform.translate(
                              offset: offset,
                              child: Transform.rotate(
                                angle: angle,
                                child: Transform.scale(
                                  scale: scale,
                                  alignment: Alignment.topCenter,
                                  child: WalletCard(
                                    account: front,
                                    currency: widget.currency,
                                    masked: widget.masked,
                                    selected: front.name == widget.selected,
                                    onMenu: () => widget.onMenu(front),
                                    semanticsLabel: '${front.name} wallet card',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous wallet',
                  onPressed: accounts.length < 2
                      ? null
                      : () => widget.onPrevious(accounts.last),
                  icon: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                Expanded(
                  child: Text(
                    'Swipe any direction · ${accounts.length} cards',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next wallet',
                  onPressed: accounts.length < 2
                      ? null
                      : () => widget.onNext(front),
                  icon: const Icon(LucideIcons.chevronRight, size: 18),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WalletAppIcons {
  static final Map<String, Uint8List?> _cache = {};
  static final Set<String> _pending = {};
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static Uint8List? iconFor(String name) {
    final key = name.trim();
    if (key.isEmpty) return null;
    if (!_cache.containsKey(key) && !_pending.contains(key)) {
      _load([key]);
    }
    return _cache[key];
  }

  static void prefetch(Iterable<String> names) {
    final missing = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty && !_cache.containsKey(n) && !_pending.contains(n))
        .toList();
    if (missing.isNotEmpty) _load(missing);
  }

  static Future<void> _load(List<String> names) async {
    _pending.addAll(names);
    try {
      final fetched = await NativeSession.channel.invokeMapMethod<String, Uint8List>(
        'walletAppIcons',
        names,
      );
      var updated = false;
      for (final name in names) {
        final bytes = fetched?[name];
        if (bytes != null && bytes.isNotEmpty) {
          _cache[name] = bytes;
          updated = true;
        } else {
          _cache[name] = null;
        }
      }
      if (updated) version.value++;
    } catch (_) {
      for (final name in names) {
        _cache[name] = null;
      }
    } finally {
      _pending.removeAll(names);
    }
  }
}

class _WalletMark extends StatelessWidget {
  final WalletAccount account;
  final double size;
  const _WalletMark({required this.account, this.size = 38});

  IconData? _genericIcon(String name) {
    switch (name.trim().toLowerCase()) {
      case 'cash':
        return LucideIcons.banknote;
      case 'bank':
        return LucideIcons.landmark;
      case 'card':
        return LucideIcons.creditCard;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
    valueListenable: _WalletAppIcons.version,
    builder: (context, _, _) {
      final appIcon = account.hasCustomArtwork
          ? null
          : _WalletAppIcons.iconFor(account.name);
      final generic = _genericIcon(account.name);
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .32),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: account.skin.colors,
                  ),
                ),
              ),
              if (account.hasCustomArtwork)
                Image.file(
                  File(account.imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else if (appIcon != null)
                Image.memory(
                  appIcon,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else if (generic != null)
                Center(
                  child: Icon(
                    generic,
                    size: size * .48,
                    color: account.skin.ink,
                  ),
                )
              else if (account.skin.assetPath != null)
                Image.asset(
                  account.skin.assetPath!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                Center(
                  child: Text(
                    account.name.isEmpty
                        ? '?'
                        : account.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: account.skin.ink,
                      fontSize: size * .34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _WalletDetail extends StatelessWidget {
  final WalletAccount account;
  final List<Entry> entries;
  final String currency;
  final bool masked;
  final bool selected;
  final VoidCallback onEdit, onFront;
  final VoidCallback? onFocus;
  const _WalletDetail({
    required this.account,
    required this.entries,
    required this.currency,
    required this.masked,
    required this.selected,
    required this.onEdit,
    required this.onFront,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext c) => PanelContent(
    header: PanelHeading(
      title: account.name,
      leading: _WalletMark(account: account, size: 40),
    ),
    footer: AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WalletCard(
          account: account,
          currency: currency,
          masked: masked,
          selected: selected,
          showMenu: false,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DetailStat(
                label: 'Balance',
                value: masked
                    ? walletMaskedAmount(currency)
                    : money(account.balance, currency),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DetailStat(
                label: 'Saved',
                value: masked
                    ? walletMaskedAmount(currency)
                    : money(
                        entries
                            .where((entry) => entry.kind == 'savings')
                            .fold(0, (sum, entry) => sum + entry.amount),
                        currency,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DetailStat(
                label: 'Planned',
                value: account.committed == 0
                    ? 'None'
                    : masked
                    ? 'Hidden'
                    : money(account.committed, currency),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (onFocus != null)
          OutlinedButton.icon(
            onPressed: onFocus,
            icon: Icon(
              selected ? LucideIcons.check : LucideIcons.slidersHorizontal,
              size: 18,
            ),
            label: Text(
              selected ? 'Finance scoped here' : 'Scope Finance to this wallet',
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(LucideIcons.sparkles, size: 18),
          label: const Text('Edit card design'),
        ),
        TextButton.icon(
          onPressed: onFront,
          icon: const Icon(LucideIcons.layers, size: 18),
          label: const Text('Move card to front'),
        ),
        const SizedBox(height: 12),
        Text(
          'RECENT ACTIVITY',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.7,
            fontWeight: FontWeight.w600,
            color: Theme.of(c).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          const EmptyState(
            'No movements yet.',
            'Assign this wallet when you save a transaction.',
            LucideIcons.wallet,
          )
        else
          for (final entry in entries.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                entry.kind == 'income'
                    ? LucideIcons.arrowDownLeft
                    : entry.kind == 'savings'
                    ? LucideIcons.piggyBank
                    : LucideIcons.arrowUpRight,
                size: 18,
              ),
              title: Text(
                entry.note.isEmpty ? entry.category : entry.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.day} · ${entry.category}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${entry.kind == 'income' ? '+' : '−'}${money(entry.amount, currency)}',
                style: TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 11,
                  color: entry.kind == 'income'
                      ? Theme.of(c).colorScheme.onSurface
                      : Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      ],
    ),
  );
}

class _DetailStat extends StatelessWidget {
  final String label, value;
  const _DetailStat({required this.label, required this.value});
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(c).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(c).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Geist Mono',
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WalletMenu extends StatelessWidget {
  final WalletAccount account;
  final bool selected;
  final VoidCallback onEdit, onFront, onAdd;
  final VoidCallback? onFocus;
  final ValueChanged<bool> onIncluded;
  const _WalletMenu({
    required this.account,
    required this.selected,
    required this.onEdit,
    required this.onFront,
    required this.onIncluded,
    required this.onAdd,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext c) => PanelContent(
    header: PanelHeading(
      title: account.name,
      leading: _WalletMark(account: account, size: 40),
    ),
    footer: AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
    child: Column(
      children: [
        if (onFocus != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              selected ? LucideIcons.check : LucideIcons.slidersHorizontal,
              size: 20,
            ),
            title: Text(
              selected ? 'Finance scoped here' : 'Scope Finance to this wallet',
            ),
            subtitle: const Text(
              'Month totals, safe to spend, chart, planner and timeline.',
              style: TextStyle(fontSize: 11),
            ),
            onTap: onFocus,
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.sparkles, size: 20),
          title: const Text('Edit card design'),
          onTap: onEdit,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.layers, size: 20),
          title: const Text('Move card to front'),
          onTap: onFront,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include in net total'),
          subtitle: const Text(
            'Excluded cards stay visible but do not change the top balance.',
            style: TextStyle(fontSize: 11),
          ),
          value: account.included,
          onChanged: onIncluded,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.plus, size: 20),
          title: const Text('Add another wallet'),
          onTap: onAdd,
        ),
      ],
    ),
  );
}

class _WalletDesignSheet extends ConsumerStatefulWidget {
  final WalletAccount account;
  final AppData data;
  const _WalletDesignSheet({required this.account, required this.data});
  @override
  ConsumerState<_WalletDesignSheet> createState() => _WalletDesignSheetState();
}

class _WalletDesignSheetState extends ConsumerState<_WalletDesignSheet> {
  late String style;
  late String? image;
  late double scale, dx, dy;
  late bool included;
  final newFiles = <String>[];
  bool busy = false, saved = false, repositioning = false;
  double startScale = 1;
  Offset startOffset = Offset.zero, startFocal = Offset.zero;
  Size previewSize = Size.zero;

  String get name => widget.account.name;
  WalletSkin get skin => WalletSkin.resolve(name, style);
  bool get custom => style == 'custom' && image != null;

  @override
  void initState() {
    super.initState();
    final prefs = widget.data.prefs;
    style = prefs['wallet:$name:style'] ?? widget.account.skin.id;
    image = prefs['wallet:$name:image'];
    scale = double.tryParse(prefs['wallet:$name:scale'] ?? '') ?? 1;
    dx = double.tryParse(prefs['wallet:$name:dx'] ?? '') ?? 0;
    dy = double.tryParse(prefs['wallet:$name:dy'] ?? '') ?? 0;
    included = prefs['wallet:$name:include'] != 'false';
  }

  @override
  void dispose() {
    if (!saved) {
      for (final path in newFiles) {
        if (path != image) unawaited(discardWalletCardImage(path));
      }
    }
    super.dispose();
  }

  WalletAccount get preview => WalletAccount(
    name: name,
    balance: widget.account.balance,
    skin: skin,
    imagePath: custom ? image : null,
    scale: scale,
    dx: dx,
    dy: dy,
    included: included,
    movements: widget.account.movements,
  );

  Future<void> _chooseArtwork() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await pickWalletCardImage();
      if (file == null || !mounted) return;
      setState(() {
        newFiles.add(file.path);
        image = file.path;
        style = 'custom';
        scale = 1;
        dx = 0;
        dy = 0;
        repositioning = false;
      });
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is FormatException ? e.message : 'Could not open that image.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final db = ref.read(databaseProvider);
      final oldImage = widget.data.prefs['wallet:$name:image'];
      await db.transaction(() async {
        await db.pref('wallet:$name:style', style);
        if (image == null) {
          await (db.delete(
            db.preferences,
          )..where((t) => t.key.equals('wallet:$name:image'))).go();
        } else {
          await db.pref('wallet:$name:image', image!);
        }
        await db.pref('wallet:$name:scale', scale.toStringAsFixed(3));
        await db.pref('wallet:$name:dx', dx.toStringAsFixed(3));
        await db.pref('wallet:$name:dy', dy.toStringAsFixed(3));
        await db.pref('wallet:$name:include', '$included');
      });
      saved = true;
      for (final path in newFiles) {
        if (path != image) await discardWalletCardImage(path);
      }
      if (oldImage != null && oldImage != image) {
        await discardWalletCardImage(oldImage);
      }
      if (mounted) {
        dataToast(context, 'Wallet', DataAction.saved);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not save this card. Try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PanelContent(
    header: PanelHeading(title: '$name card'),
    footer: AppButton(label: 'Save card', busy: busy, onPressed: _save),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (c, constraints) {
            previewSize = constraints.biggest;
            return GestureDetector(
              onScaleStart: !repositioning || !custom
                  ? null
                  : (details) {
                      startScale = scale;
                      startOffset = Offset(dx, dy);
                      startFocal = details.focalPoint;
                    },
              onScaleUpdate: !repositioning || !custom
                  ? null
                  : (details) {
                      setState(() {
                        scale = (startScale * details.scale).clamp(1.0, 4.0);
                        dx =
                            (startOffset.dx +
                                    (details.focalPoint.dx - startFocal.dx) /
                                        previewSize.width)
                                .clamp(-1.5, 1.5);
                        dy =
                            (startOffset.dy +
                                    (details.focalPoint.dy - startFocal.dy) /
                                        previewSize.height)
                                .clamp(-1.5, 1.5);
                      });
                    },
              child: WalletCard(
                account: preview,
                currency: widget.data.currency,
                masked: false,
                showMenu: false,
              ),
            );
          },
        ),
        if (repositioning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Drag to reposition, pinch to zoom. The amount always stays on top.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 14),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: WalletSkin.presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (c, i) {
              final option = WalletSkin.presets[i];
              return _SkinTile(
                skin: option,
                selected: style == option.id,
                onTap: () => setState(() {
                  style = option.id;
                  repositioning = false;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: image == null ? 'Upload card artwork' : 'Replace card artwork',
          icon: LucideIcons.image,
          secondary: true,
          busy: busy,
          onPressed: _chooseArtwork,
        ),
        if (image != null) ...[
          const SizedBox(height: 8),
          if (style != 'custom')
            AppButton(
              label: 'Use uploaded artwork',
              icon: LucideIcons.sparkles,
              secondary: true,
              onPressed: () => setState(() {
                style = 'custom';
                repositioning = false;
              }),
            )
          else ...[
            AppButton(
              label: repositioning
                  ? 'Done repositioning'
                  : 'Reposition artwork',
              icon: LucideIcons.crop,
              secondary: true,
              onPressed: () => setState(() => repositioning = !repositioning),
            ),
            AppButton(
              label: 'Reset artwork position',
              icon: LucideIcons.rotateCcw,
              quiet: true,
              onPressed: () => setState(() {
                scale = 1;
                dx = 0;
                dy = 0;
              }),
            ),
            AppButton(
              label: 'Remove artwork',
              icon: LucideIcons.trash2,
              quiet: true,
              destructive: true,
              onPressed: () => setState(() {
                image = null;
                style = skin.id;
                repositioning = false;
                scale = 1;
                dx = 0;
                dy = 0;
              }),
            ),
          ],
        ],
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include in net total'),
          subtitle: const Text(
            'Excluded cards stay visible but do not change the top balance.',
            style: TextStyle(fontSize: 11),
          ),
          value: included,
          onChanged: (value) => setState(() => included = value),
        ),
      ],
    ),
  );
}

class _SkinTile extends StatelessWidget {
  final WalletSkin skin;
  final bool selected;
  final VoidCallback onTap;
  const _SkinTile({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final outline = Theme.of(c).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '${skin.label} card design',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.duration(c, 150),
          width: 88,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? outline : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: skin.colors,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (skin.assetPath != null)
                        Image.asset(
                          skin.assetPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (selected)
                        const Center(
                          child: Icon(
                            LucideIcons.check,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                skin.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWalletSheet extends ConsumerStatefulWidget {
  final AppData data;
  const _AddWalletSheet({required this.data});
  @override
  ConsumerState<_AddWalletSheet> createState() => _AddWalletSheetState();
}

class _AddWalletSheetState extends ConsumerState<_AddWalletSheet> {
  final name = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (busy) return;
    final value = name.text.trim();
    if (value.isEmpty) {
      toast(context, 'Enter a wallet name.', error: true);
      return;
    }
    if (value.length > 24) {
      toast(context, 'Keep the wallet name under 24 characters.', error: true);
      return;
    }
    if (widget.data.walletMethods.any(
      (method) => method.toLowerCase() == value.toLowerCase(),
    )) {
      toast(context, 'That wallet already exists.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final methods = [...widget.data.methods, value];
      final stored = [...walletStoredOrder(widget.data.prefs)]..remove(value);
      final order = [...stored, value];
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        await db.pref('methods', jsonEncode(methods));
        await db.pref('walletOrder', jsonEncode(order));
        await db.pref('wallet:$value:style', WalletSkin.byName(value).id);
      });
      if (mounted) {
        dataToast(context, 'Payment method', DataAction.saved);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not add this wallet. Try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PanelContent(
    header: const PanelHeading(title: 'Add wallet'),
    footer: AppButton(
      label: 'Add wallet',
      icon: LucideIcons.plus,
      busy: busy,
      onPressed: _add,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: name,
          builder: (c, value, _) {
            final label = value.text.trim().isEmpty
                ? 'New wallet'
                : value.text.trim();
            final skin = WalletSkin.byName(label);
            return WalletCard(
              account: WalletAccount(
                name: label,
                balance: 0,
                skin: skin,
                imagePath: null,
                scale: 1,
                dx: 0,
                dy: 0,
                included: true,
                movements: 0,
              ),
              currency: widget.data.currency,
              masked: false,
              showMenu: false,
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Wallet or payment method',
            helperText:
                'Balances come from transactions assigned to this method.',
            counterText: '',
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 12),
        Text(
          'The card artwork is chosen from the name. You can change it after adding, or upload your own card design.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: Theme.of(c).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
