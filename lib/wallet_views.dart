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
  final Set<String> _removing = {};

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
    if (_removing.isNotEmpty) {
      final activeLower = widget.data.walletMethods
          .map((m) => m.trim().toLowerCase())
          .toSet();
      _removing.removeWhere((name) => !activeLower.contains(name));
    }
  }

  List<WalletAccount> _accounts() {
    bool keep(WalletAccount a) =>
        !_removing.contains(a.name.trim().toLowerCase());
    final provided = widget.accounts;
    if (provided != null &&
        _sameNames(provided.map((a) => a.name).toList(), order)) {
      return _removing.isEmpty ? provided : provided.where(keep).toList();
    }
    final list = walletAccounts(
      widget.data,
      widget.data.orderedWalletNames(order),
      widget.committed,
    );
    return _removing.isEmpty ? list : list.where(keep).toList();
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

  Future<void> _removeWallet(WalletAccount account) async {
    if (!await confirm(
      context,
      'Remove ${account.name}?',
      'It will be removed from Wallets and Payment methods. Existing transactions remain in your records.',
    )) {
      return;
    }
    if (!mounted) return;
    final targetLower = account.name.trim().toLowerCase();
    final previousOrder = List<String>.from(order);
    final previousWallet = widget.wallet?.trim().toLowerCase() == targetLower
        ? widget.wallet
        : null;
    setState(() {
      _removing.add(targetLower);
      order = [...order]
        ..removeWhere((w) => w.trim().toLowerCase() == targetLower);
    });
    if (previousWallet != null) {
      widget.onWallet?.call(null);
    }
    try {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        final prefs = await db.readPreferences();
        final data = AppData(const [], const [], const [], prefs);
        final nextMethods = data.methods
            .where((m) => m.trim().toLowerCase() != targetLower)
            .toList();
        await db.pref('methods', jsonEncode(nextMethods));
        final hidden = {...data.hiddenWallets, targetLower};
        await db.pref('hiddenWallets', jsonEncode(hidden.toList()));
        final stored = [...walletStoredOrder(prefs)]
          ..removeWhere((w) => w.trim().toLowerCase() == targetLower);
        await db.pref('walletOrder', jsonEncode(stored));
        final pkg = prefs['wallet:${account.name}:package'];
        if (pkg != null && pkg.isNotEmpty) {
          final config = AutomationSync.config(data);
          final apps = Set<String>.from(config['apps'] as List? ?? []);
          if (apps.remove(pkg)) {
            config['apps'] = apps.toList();
            await db.pref('automation', jsonEncode(config));
          }
        }
      });
      unawaited(
        db.readAll().then(AutomationSync.configure).catchError((Object _) {}),
      );
      if (mounted) {
        dataToast(context, 'Payment method', DataAction.deleted);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _removing.remove(targetLower);
          order = previousOrder;
        });
        if (previousWallet != null) {
          widget.onWallet?.call(previousWallet);
        }
        toast(context, 'Could not remove this wallet. Try again.', error: true);
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
          onTransfer: () {
            Navigator.pop(sheet);
            _transfer(account.name);
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
        onTransfer: () {
          Navigator.pop(sheet);
          _transfer(account.name);
        },
        onIncluded: (value) {
          Navigator.pop(sheet);
          _setIncluded(account, value);
        },
        onAdd: () {
          Navigator.pop(sheet);
          _addWallet();
        },
        onRemove: () {
          Navigator.pop(sheet);
          _removeWallet(account);
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

  Future<void> _transfer([String? fromWallet]) async {
    final accounts = _accounts();
    if (accounts.length < 2) {
      toast(
        context,
        'Add another wallet first to transfer money.',
        error: true,
      );
      return;
    }
    await panel(
      context,
      WalletTransferSheet(
        data: widget.data,
        initialFrom: fromWallet ?? widget.wallet,
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final accounts = _accounts();
    _WalletAppIcons.prefetch(accounts, context: c);
    final included = accounts.where((a) => a.included).toList();
    final scoped = widget.wallet == null
        ? included
        : accounts
              .where(
                (a) => a.name.toLowerCase() == widget.wallet!.toLowerCase(),
              )
              .toList();
    final total = scoped.fold(0, (sum, a) => sum + a.balance);
    final assets = scoped
        .where((a) => a.balance > 0)
        .fold(0, (sum, a) => sum + a.balance);
    final liabilities = scoped
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
            count: scoped.length,
            wallet: widget.wallet,
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
          onTransfer: () => _transfer(),
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
  final String? wallet;
  final String currency;
  final bool masked;
  final VoidCallback onToggle;
  const _WalletTotalCard({
    required this.total,
    required this.assets,
    required this.liabilities,
    required this.count,
    this.wallet,
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
                    wallet == null
                        ? 'TOTAL BALANCE'
                        : 'WALLET BALANCE · ${wallet!.toUpperCase()}',
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
              wallet == null
                  ? 'All wallets · all time, in $currency'
                  : '$wallet · all time, in $currency',
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
  final VoidCallback onTransfer;
  const _WalletToolbar({
    required this.count,
    required this.view,
    required this.onView,
    required this.onAdd,
    required this.onTransfer,
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
          tooltip: 'Transfer money',
          onPressed: withFeedback(onTransfer),
          style: IconButton.styleFrom(
            minimumSize: const Size(38, 38),
            maximumSize: const Size(38, 38),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(LucideIcons.arrowLeftRight, size: 17),
        ),
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
    _WalletAppIcons.prefetch(accounts, context: c);
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

enum _DeckMotion { idle, dragging, committingNext, committingPrev, cancelling }

class _DeckSlotPose {
  final int index;
  final double tx, ty, scale, angle, scrim, alpha;
  final int zOrder;
  const _DeckSlotPose({
    required this.index,
    this.tx = 0,
    this.ty = 0,
    this.scale = 1,
    this.angle = 0,
    this.scrim = 0,
    this.alpha = 1,
    required this.zOrder,
  });
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
  static const double _peekStep = 14.0;
  static const double _scaleStep = 0.045;
  static const double _scrimStep = 0.085;
  static const double _prevSwapAt = 0.48;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  final ValueNotifier<double> _dragPx = ValueNotifier<double>(0);
  late final Listenable _repaint = Listenable.merge([_controller, _dragPx]);

  _DeckMotion _mode = _DeckMotion.idle;
  double _flightFromPx = 0;
  double _deckWidth = 320;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant _WalletDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.accounts.length < 2 ||
            oldWidget.accounts.length != widget.accounts.length) &&
        _mode != _DeckMotion.idle) {
      _mode = _DeckMotion.idle;
      _dragPx.value = 0;
      _flightFromPx = 0;
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    _dragPx.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final completedMode = _mode;
    _mode = _DeckMotion.idle;
    _dragPx.value = 0;
    _flightFromPx = 0;
    _controller.reset();
    if (widget.accounts.length < 2) return;
    if (completedMode == _DeckMotion.committingNext) {
      widget.onNext(widget.accounts.first);
    } else if (completedMode == _DeckMotion.committingPrev) {
      widget.onPrevious(widget.accounts.last);
    }
  }

  bool get _isCommitting =>
      _mode == _DeckMotion.committingNext ||
      _mode == _DeckMotion.committingPrev;

  double _slotY(double slot, int behind) => (behind - slot) * _peekStep;
  double _slotScale(double slot) => 1.0 - _scaleStep * slot;
  double _slotScrim(double slot) => (_scrimStep * slot).clamp(0.0, 0.28);

  void _onDragStart(DragStartDetails details) {
    if (_isCommitting) return;
    if (_mode == _DeckMotion.cancelling) {
      final k = Motion.settle.transform(_controller.value);
      _dragPx.value = ui.lerpDouble(_flightFromPx, 0.0, k) ?? 0.0;
      _controller.stop();
      _controller.reset();
    }
    _mode = _DeckMotion.dragging;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_mode != _DeckMotion.dragging) return;
    if (widget.accounts.length < 2) {
      _dragPx.value = (_dragPx.value + details.delta.dx * 0.28).clamp(
        -40.0,
        40.0,
      );
      return;
    }
    _dragPx.value = (_dragPx.value + details.delta.dx).clamp(
      -_deckWidth * 1.1,
      _deckWidth * 1.1,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (_mode != _DeckMotion.dragging) return;
    _finishDrag(details.velocity.pixelsPerSecond.dx);
  }

  void _onDragCancel() {
    if (_mode != _DeckMotion.dragging) return;
    _finishDrag(0);
  }

  void _finishDrag(double vx) {
    if (widget.accounts.length < 2) {
      _animateCancel();
      return;
    }
    final dx = _dragPx.value;
    final w = _deckWidth;
    final commitNext = dx < -w * 0.20 || (vx < -460 && dx < 24);
    final commitPrev = dx > w * 0.20 || (vx > 460 && dx > -24);
    if (commitNext) {
      _startCommit(next: true, velocityX: vx);
    } else if (commitPrev) {
      _startCommit(next: false, velocityX: vx);
    } else {
      _animateCancel();
    }
  }

  void _startCommit({required bool next, double velocityX = 0}) {
    if (widget.accounts.length < 2 || _isCommitting) return;
    if (Motion.duration(context, 280) == Duration.zero) {
      _mode = _DeckMotion.idle;
      _dragPx.value = 0;
      _flightFromPx = 0;
      _controller.reset();
      if (next) {
        widget.onNext(widget.accounts.first);
      } else {
        widget.onPrevious(widget.accounts.last);
      }
      return;
    }
    _flightFromPx = _dragPx.value;
    _mode = next ? _DeckMotion.committingNext : _DeckMotion.committingPrev;
    final ms = (290 - velocityX.abs() / 22).clamp(180, 300).round();
    _controller.duration = Motion.duration(context, ms);
    _controller.forward(from: 0);
  }

  void _animateCancel() {
    if (Motion.duration(context, 220) == Duration.zero ||
        _dragPx.value.abs() < 0.5) {
      _mode = _DeckMotion.idle;
      _dragPx.value = 0;
      _flightFromPx = 0;
      _controller.reset();
      return;
    }
    _flightFromPx = _dragPx.value;
    _mode = _DeckMotion.cancelling;
    _controller.duration = Motion.duration(context, 220);
    _controller.forward(from: 0);
  }

  List<_DeckSlotPose> _poses(double width, int n, int behind) {
    final swipeRange = math.max(120.0, width * 0.48);

    List<_DeckSlotPose> restPoses() => [
      for (var i = behind; i >= 0; i--)
        _DeckSlotPose(
          index: i,
          ty: _slotY(i.toDouble(), behind),
          scale: _slotScale(i.toDouble()),
          scrim: _slotScrim(i.toDouble()),
          zOrder: behind - i,
        ),
    ];

    List<_DeckSlotPose> dragPoses(double dx) {
      if (n == 1) {
        return [
          _DeckSlotPose(
            index: 0,
            tx: dx,
            angle: (dx / width).clamp(-1.0, 1.0) * 0.04,
            zOrder: 0,
          ),
        ];
      }
      if (dx <= 0) {
        final t = (-dx / swipeRange).clamp(0.0, 1.0);
        final poses = <_DeckSlotPose>[];
        if (n > 4 && t > 0.001) {
          final slot = 4.0 - t;
          poses.add(
            _DeckSlotPose(
              index: 4,
              ty: _slotY(slot, behind),
              scale: _slotScale(slot),
              scrim: _slotScrim(slot),
              alpha: t,
              zOrder: -1,
            ),
          );
        }
        for (var i = behind; i >= 1; i--) {
          final slot = i - t;
          poses.add(
            _DeckSlotPose(
              index: i,
              ty: _slotY(slot, behind),
              scale: _slotScale(slot),
              scrim: _slotScrim(slot),
              zOrder: behind - i,
            ),
          );
        }
        poses.add(
          _DeckSlotPose(
            index: 0,
            tx: dx,
            ty: _slotY(0, behind),
            scale: ui.lerpDouble(1.0, 0.95, t)!,
            angle: (dx / width).clamp(-1.0, 1.0) * 0.075,
            zOrder: behind + 1,
          ),
        );
        return poses;
      }

      // Dragging right previews bringing the previous card forward.
      final t = (dx / swipeRange).clamp(0.0, 1.0);
      final u = t * (_prevSwapAt - 0.02);
      final k = Curves.easeOutCubic.transform(u / _prevSwapAt);
      final backSlot = behind.toDouble();
      final prevIndex = n - 1;
      final poses = <_DeckSlotPose>[];

      poses.add(
        _DeckSlotPose(
          index: prevIndex,
          tx: -width * 0.72 * k,
          ty: ui.lerpDouble(
            _slotY(backSlot, behind),
            _slotY(0, behind) - 4,
            k,
          )!,
          scale: ui.lerpDouble(_slotScale(backSlot), 0.94, k)!,
          angle: -0.07 * k,
          scrim: ui.lerpDouble(_slotScrim(backSlot), 0.04, k)!,
          alpha: n > 4 ? (u / 0.22).clamp(0.0, 1.0) : 1.0,
          zOrder: -1,
        ),
      );

      final maxMiddle = n <= 4 ? n - 2 : 3;
      for (var i = maxMiddle; i >= 1; i--) {
        final slot = i + u;
        poses.add(
          _DeckSlotPose(
            index: i,
            ty: _slotY(slot, behind),
            scale: _slotScale(slot),
            scrim: _slotScrim(slot),
            zOrder: behind - i,
          ),
        );
      }

      final c0Slot = u / _prevSwapAt * 0.5;
      poses.add(
        _DeckSlotPose(
          index: 0,
          tx: dx * 0.42,
          ty: _slotY(c0Slot, behind),
          scale: _slotScale(c0Slot),
          angle: (dx / width).clamp(0.0, 1.0) * 0.05,
          scrim: _slotScrim(c0Slot),
          zOrder: behind + 1,
        ),
      );
      return poses;
    }

    switch (_mode) {
      case _DeckMotion.idle:
        return restPoses();
      case _DeckMotion.dragging:
        return dragPoses(_dragPx.value);
      case _DeckMotion.cancelling:
        final k = Motion.settle.transform(_controller.value);
        final dx = ui.lerpDouble(_flightFromPx, 0.0, k)!;
        return dragPoses(dx);
      case _DeckMotion.committingNext:
        final u = _controller.value;
        final startT = (-_flightFromPx / swipeRange).clamp(0.0, 1.0);
        final t = ui.lerpDouble(startT, 1.0, Curves.easeOutCubic.transform(u))!;
        final peakDx = math.min(_flightFromPx, -width * 0.72);
        final swapAt = _flightFromPx <= -width * 0.65 ? 0.14 : 0.46;
        final backSlot = behind.toDouble();
        final midY = ui.lerpDouble(
          _slotY(0, behind),
          _slotY(backSlot, behind),
          0.35,
        )!;
        final poses = <_DeckSlotPose>[];

        if (n > 4) {
          final slot = 4.0 - t;
          poses.add(
            _DeckSlotPose(
              index: 4,
              ty: _slotY(slot, behind),
              scale: _slotScale(slot),
              scrim: _slotScrim(slot),
              alpha: t,
              zOrder: 0,
            ),
          );
        }
        for (var i = behind; i >= 1; i--) {
          final slot = i - t;
          poses.add(
            _DeckSlotPose(
              index: i,
              ty: _slotY(slot, behind),
              scale: _slotScale(slot),
              scrim: _slotScrim(slot),
              zOrder: (behind - i) + 1,
            ),
          );
        }

        if (u < swapAt) {
          final k = Curves.easeOutCubic.transform(u / swapAt);
          final tx = ui.lerpDouble(_flightFromPx, peakDx, k)!;
          poses.add(
            _DeckSlotPose(
              index: 0,
              tx: tx,
              ty: ui.lerpDouble(_slotY(0, behind), midY, k)!,
              scale: ui.lerpDouble(ui.lerpDouble(1.0, 0.95, startT)!, 0.93, k)!,
              angle: (tx / width).clamp(-1.0, 1.0) * 0.075,
              zOrder: behind + 2,
            ),
          );
        } else {
          final k = Curves.easeInOutCubic.transform(
            (u - swapAt) / (1.0 - swapAt),
          );
          poses.add(
            _DeckSlotPose(
              index: 0,
              tx: ui.lerpDouble(peakDx, 0.0, k)!,
              ty: ui.lerpDouble(midY, _slotY(backSlot, behind), k)!,
              scale: ui.lerpDouble(0.93, _slotScale(backSlot), k)!,
              angle: ui.lerpDouble(
                (peakDx / width).clamp(-1.0, 1.0) * 0.075,
                0.0,
                k,
              )!,
              scrim: ui.lerpDouble(0.0, _slotScrim(backSlot), k)!,
              alpha: n > 4 ? (1.0 - k) : 1.0,
              zOrder: -1,
            ),
          );
        }
        poses.sort((a, b) => a.zOrder.compareTo(b.zOrder));
        return poses;

      case _DeckMotion.committingPrev:
        final startU =
            (_flightFromPx / swipeRange).clamp(0.0, 1.0) * (_prevSwapAt - 0.02);
        final u = ui.lerpDouble(
          startU,
          1.0,
          Curves.easeInOutCubic.transform(_controller.value),
        )!;
        final backSlot = behind.toDouble();
        final prevIndex = n - 1;
        final startC0Tx = _flightFromPx * 0.42;
        final peakC0Tx = math.max(startC0Tx, width * 0.22);
        final poses = <_DeckSlotPose>[];

        final maxMiddle = n <= 4 ? n - 2 : 3;
        for (var i = maxMiddle; i >= 1; i--) {
          final slot = i + u;
          final alpha = (n > 4 && i == 3)
              ? (1.0 - (u - 0.35) / 0.45).clamp(0.0, 1.0)
              : 1.0;
          poses.add(
            _DeckSlotPose(
              index: i,
              ty: _slotY(slot, behind),
              scale: _slotScale(slot),
              scrim: _slotScrim(slot),
              alpha: alpha,
              zOrder: behind - i,
            ),
          );
        }

        if (u < _prevSwapAt) {
          final localT = (u - startU) / (_prevSwapAt - startU);
          final kAll = Curves.easeOutCubic.transform(u / _prevSwapAt);
          final c0Tx = ui.lerpDouble(
            startC0Tx,
            peakC0Tx,
            Curves.easeOut.transform(localT.clamp(0.0, 1.0)),
          )!;
          final c0Slot = (u / _prevSwapAt) * 0.5;
          poses.add(
            _DeckSlotPose(
              index: 0,
              tx: c0Tx,
              ty: _slotY(c0Slot, behind),
              scale: _slotScale(c0Slot),
              angle: (c0Tx / width).clamp(0.0, 1.0) * 0.05,
              scrim: _slotScrim(c0Slot),
              zOrder: behind + 1,
            ),
          );
          poses.add(
            _DeckSlotPose(
              index: prevIndex,
              tx: -width * 0.72 * kAll,
              ty: ui.lerpDouble(
                _slotY(backSlot, behind),
                _slotY(0, behind) - 4,
                kAll,
              )!,
              scale: ui.lerpDouble(_slotScale(backSlot), 0.94, kAll)!,
              angle: -0.07 * kAll,
              scrim: ui.lerpDouble(_slotScrim(backSlot), 0.04, kAll)!,
              alpha: n > 4 ? (u / 0.22).clamp(0.0, 1.0) : 1.0,
              zOrder: -1,
            ),
          );
        } else {
          final k = Curves.easeOutCubic.transform(
            (u - _prevSwapAt) / (1.0 - _prevSwapAt),
          );
          final kEase = Curves.easeInOutCubic.transform(
            (u - _prevSwapAt) / (1.0 - _prevSwapAt),
          );
          final c0Slot = ui.lerpDouble(0.5, 1.0, kEase)!;
          poses.add(
            _DeckSlotPose(
              index: 0,
              tx: ui.lerpDouble(peakC0Tx, 0.0, kEase)!,
              ty: _slotY(c0Slot, behind),
              scale: _slotScale(c0Slot),
              angle: ui.lerpDouble(
                (peakC0Tx / width).clamp(0.0, 1.0) * 0.05,
                0.0,
                kEase,
              )!,
              scrim: _slotScrim(c0Slot),
              zOrder: behind + 1,
            ),
          );
          poses.add(
            _DeckSlotPose(
              index: prevIndex,
              tx: ui.lerpDouble(-width * 0.72, 0.0, k)!,
              ty: ui.lerpDouble(_slotY(0, behind) - 4, _slotY(0, behind), k)!,
              scale: ui.lerpDouble(0.94, 1.0, k)!,
              angle: ui.lerpDouble(-0.07, 0.0, k)!,
              scrim: ui.lerpDouble(0.04, 0.0, k)!,
              zOrder: behind + 2,
            ),
          );
        }
        poses.sort((a, b) => a.zOrder.compareTo(b.zOrder));
        return poses;
    }
  }

  @override
  Widget build(BuildContext c) {
    final accounts = widget.accounts;
    if (accounts.isEmpty) return const SizedBox.shrink();
    final n = accounts.length;
    final front = accounts.first;
    final behind = math.min(3, n - 1);
    final dark = Theme.of(c).brightness == Brightness.dark;

    // Prebuild card widgets outside AnimatedBuilder so drag/animation frames
    // only update compositor transforms without rebuilding WalletCard subtrees.
    final indices = <int>{
      for (var i = 0; i <= behind; i++) i,
      if (n > 4) 4,
      if (n > 1) n - 1,
    };
    final cardWidgets = <int, Widget>{
      for (final i in indices)
        i: RepaintBoundary(
          key: ValueKey(accounts[i].name),
          child: WalletCard(
            account: accounts[i],
            currency: widget.currency,
            masked: widget.masked,
            selected: accounts[i].name == widget.selected,
            showMenu: i == 0,
            onMenu: i == 0 ? () => widget.onMenu(accounts[i]) : null,
            semanticsLabel: i == 0 ? '${accounts[i].name} wallet card' : null,
          ),
        ),
    };

    return LayoutBuilder(
      builder: (c, constraints) {
        final width = constraints.maxWidth;
        _deckWidth = width;
        final cardHeight = width / 1.586;
        final stackHeight = cardHeight + behind * _peekStep + 8;

        return Column(
          children: [
            Semantics(
              label:
                  '${front.name} wallet, ${widget.masked ? 'amount hidden' : money(front.balance, widget.currency)}, card 1 of $n',
              onIncrease: n < 2 ? null : () => _startCommit(next: true),
              onDecrease: n < 2 ? null : () => _startCommit(next: false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isCommitting ? null : () => widget.onOpen(front),
                onLongPress: _isCommitting ? null : () => widget.onMenu(front),
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: SizedBox(
                  height: stackHeight,
                  child: AnimatedBuilder(
                    animation: _repaint,
                    builder: (c, _) {
                      final poses = _poses(width, n, behind);
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          for (final pose in poses)
                            if (pose.alpha > 0.005)
                              Positioned(
                                key: ValueKey(
                                  'slot-${accounts[pose.index].name}',
                                ),
                                top: 0,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  ignoring: pose.index != 0,
                                  child: Transform.translate(
                                    offset: Offset(pose.tx, pose.ty),
                                    child: Transform.rotate(
                                      angle: pose.angle,
                                      alignment: Alignment.center,
                                      child: Transform.scale(
                                        scale: pose.scale,
                                        alignment: Alignment.topCenter,
                                        child: _DeckCardShell(
                                          dark: dark,
                                          selected:
                                              accounts[pose.index].name ==
                                              widget.selected,
                                          scrim: pose.scrim,
                                          alpha: pose.alpha,
                                          child: cardWidgets[pose.index]!,
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
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous wallet',
                  onPressed: n < 2 ? null : () => _startCommit(next: false),
                  icon: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                Expanded(
                  child: Text(
                    n == 1 ? '1 wallet card' : 'Swipe left or right · $n cards',
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
                  onPressed: n < 2 ? null : () => _startCommit(next: true),
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

class _DeckCardShell extends StatelessWidget {
  final bool dark;
  final bool selected;
  final double scrim;
  final double alpha;
  final Widget child;
  const _DeckCardShell({
    required this.dark,
    required this.selected,
    required this.scrim,
    required this.alpha,
    required this.child,
  });

  @override
  Widget build(BuildContext c) {
    final radius = BorderRadius.circular(18);
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .42 : .16),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: selected
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: dark ? .12 : .24),
                  width: .8,
                ),
          color: scrim > 0.005 ? Colors.black.withValues(alpha: scrim) : null,
        ),
        child: child,
      ),
    );
    if (alpha < 0.999) {
      result = Opacity(opacity: alpha.clamp(0.0, 1.0), child: result);
    }
    return result;
  }
}

class _WalletAppIcons {
  static final Map<String, MemoryImage?> _cache = {};
  static final Set<String> _pending = {};
  static final Set<String> _precached = {};
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String _requestToken(String name, String? packageName) {
    final pkg = packageName?.trim() ?? '';
    return pkg.isEmpty ? name : '$name|$pkg';
  }

  static String _cacheKey(String name, String? packageName) =>
      _requestToken(name.trim().toLowerCase(), packageName?.trim().toLowerCase());

  static MemoryImage? iconFor(
    String name, {
    String? packageName,
    BuildContext? context,
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return null;
    final key = _cacheKey(cleanName, packageName);
    if (!_cache.containsKey(key) && !_pending.contains(key)) {
      _load([
        (
          name: cleanName,
          key: key,
          token: _requestToken(cleanName, packageName),
        ),
      ], context: context);
    }
    final provider = _cache[key];
    if (provider != null && context != null && _precached.add(key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          unawaited(precacheImage(provider, context).catchError((Object _) {}));
        }
      });
    }
    return provider;
  }

  static bool isPending(String name, {String? packageName}) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;
    final key = _cacheKey(cleanName, packageName);
    return !_cache.containsKey(key);
  }

  static void prefetch(
    Iterable<WalletAccount> accounts, {
    BuildContext? context,
  }) {
    final missing = <({String name, String key, String token})>[];
    for (final a in accounts) {
      if (a.hasCustomArtwork) continue;
      final cleanName = a.name.trim();
      if (cleanName.isEmpty) continue;
      final key = _cacheKey(cleanName, a.packageName);
      final cached = _cache[key];
      if (cached != null && context != null && _precached.add(key)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            unawaited(precacheImage(cached, context).catchError((Object _) {}));
          }
        });
      }
      if (!_cache.containsKey(key) && !_pending.contains(key)) {
        missing.add((
          name: cleanName,
          key: key,
          token: _requestToken(cleanName, a.packageName),
        ));
      }
    }
    if (missing.isNotEmpty) _load(missing, context: context);
  }

  static Future<void> _load(
    List<({String name, String key, String token})> items, {
    BuildContext? context,
  }) async {
    final keys = items.map((e) => e.key).toList();
    _pending.addAll(keys);
    try {
      final fetched = await NativeSession.channel
          .invokeMapMethod<String, Uint8List>(
            'walletAppIcons',
            items.map((e) => e.token).toList(),
          );
      var updated = false;
      for (final item in items) {
        final bytes = fetched?[item.name];
        if (bytes != null && bytes.isNotEmpty) {
          final provider = MemoryImage(bytes);
          _cache[item.key] = provider;
          if (context != null && context.mounted && _precached.add(item.key)) {
            await precacheImage(provider, context).catchError((Object _) {});
          }
          updated = true;
        } else {
          if (_cache[item.key] != null || !_cache.containsKey(item.key)) {
            updated = true;
          }
          _cache[item.key] = null;
        }
      }
      if (updated) version.value++;
    } on MissingPluginException {
      var updated = false;
      for (final item in items) {
        if (!_cache.containsKey(item.key)) updated = true;
        _cache[item.key] = null;
      }
      if (updated) version.value++;
    } catch (_) {
      // Allow retry on transient platform channel errors instead of caching null.
    } finally {
      _pending.removeAll(keys);
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
      final generic = _genericIcon(account.name);
      final hasPackage = (account.packageName?.trim() ?? '').isNotEmpty;
      if (!account.hasCustomArtwork && !hasPackage && generic != null) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              generic,
              size: size * .76,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      }
      final appIcon = account.hasCustomArtwork
          ? null
          : _WalletAppIcons.iconFor(
              account.name,
              packageName: account.packageName,
              context: context,
            );
      if (appIcon != null) {
        return SizedBox(
          width: size,
          height: size,
          child: Image(
            image: appIcon,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      }
      if (!account.hasCustomArtwork &&
          _WalletAppIcons.isPending(
            account.name,
            packageName: account.packageName,
          )) {
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(size * .26),
            ),
          ),
        );
      }
      if (!account.hasCustomArtwork && generic != null) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              generic,
              size: size * .76,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      }
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
  final VoidCallback onEdit, onFront, onTransfer;
  final VoidCallback? onFocus;
  const _WalletDetail({
    required this.account,
    required this.entries,
    required this.currency,
    required this.masked,
    required this.selected,
    required this.onEdit,
    required this.onFront,
    required this.onTransfer,
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
          onPressed: onTransfer,
          icon: const Icon(LucideIcons.arrowLeftRight, size: 18),
          label: const Text('Transfer money'),
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
            Builder(
              builder: (context) {
                final isIn =
                    entry.kind == 'income' || entry.kind == 'transfer_in';
                final isTransfer =
                    entry.kind == 'transfer_in' || entry.kind == 'transfer_out';
                final title = isTransfer
                    ? (entry.note.isEmpty
                          ? (entry.kind == 'transfer_in'
                                ? 'From ${entry.category}'
                                : 'To ${entry.category}')
                          : entry.note)
                    : (entry.note.isEmpty ? entry.category : entry.note);
                final sub = isTransfer
                    ? '${entry.day} · ${entry.kind == 'transfer_in' ? 'Transfer from ${entry.category}' : 'Transfer to ${entry.category}'}'
                    : '${entry.day} · ${entry.category}';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    isTransfer
                        ? LucideIcons.arrowLeftRight
                        : entry.kind == 'income'
                        ? LucideIcons.arrowDownLeft
                        : entry.kind == 'savings'
                        ? LucideIcons.piggyBank
                        : LucideIcons.arrowUpRight,
                    size: 18,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    '${isIn ? '+' : '−'}${money(entry.amount, currency)}',
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 11,
                      color: isIn
                          ? Theme.of(c).colorScheme.onSurface
                          : Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
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
  final VoidCallback onEdit, onFront, onAdd, onTransfer;
  final VoidCallback? onFocus, onRemove;
  final ValueChanged<bool> onIncluded;
  const _WalletMenu({
    required this.account,
    required this.selected,
    required this.onEdit,
    required this.onFront,
    required this.onIncluded,
    required this.onAdd,
    required this.onTransfer,
    required this.onFocus,
    this.onRemove,
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
          leading: const Icon(LucideIcons.arrowLeftRight, size: 20),
          title: const Text('Transfer money'),
          subtitle: const Text(
            'Move funds to another wallet without counting as income or spend.',
            style: TextStyle(fontSize: 11),
          ),
          onTap: onTransfer,
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
        if (onRemove != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              LucideIcons.trash2,
              size: 20,
              color: Theme.of(c).colorScheme.error,
            ),
            title: Text(
              'Remove wallet',
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
            onTap: onRemove,
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
  String? _selectedPackage;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  List<String> _methodSuggestions() {
    final visible = widget.data.walletMethods
        .map((m) => m.toLowerCase())
        .toSet();
    final seen = <String>{...visible};
    final out = <String>[];
    for (final m in widget.data.methods) {
      final key = m.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(m.trim());
    }
    if (seen.add('cash')) {
      out.add('Cash');
    }
    return out;
  }

  Future<void> _pickInstalledApp() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final installed =
          (await NativeSession.channel.invokeListMethod('notificationApps') ??
                  [])
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList();
      if (!mounted) return;
      setState(() => busy = false);
      var query = '';
      final picked = await panel<Map<String, dynamic>>(
        context,
        StatefulBuilder(
          builder: (c, setLocal) {
            final filtered = query.trim().isEmpty
                ? installed
                : installed.where((app) {
                    final n = (app['name'] as String? ?? '').toLowerCase();
                    final p = (app['package'] as String? ?? '').toLowerCase();
                    final q = query.trim().toLowerCase();
                    return n.contains(q) || p.contains(q);
                  }).toList();
            return PanelContent(
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PanelHeading(title: 'Pick payment app'),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setLocal(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Search installed apps',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                ],
              ),
              footer: AppButton(
                label: 'Cancel',
                secondary: true,
                onPressed: () => Navigator.pop(c),
              ),
              scrollable: true,
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final app = filtered[i];
                  final appName = (app['name'] as String? ?? '').trim();
                  final pkg = (app['package'] as String? ?? '').trim();
                  final added = widget.data.walletMethods.any(
                    (s) => s.toLowerCase() == appName.toLowerCase(),
                  );
                  return ListTile(
                    title: Text(appName),
                    subtitle: Text(
                      pkg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: added
                        ? const Icon(LucideIcons.check, size: 18)
                        : null,
                    onTap: () => Navigator.pop(c, app),
                  );
                },
              ),
            );
          },
        ),
      );
      if (picked == null || !mounted) return;
      final appName = (picked['name'] as String? ?? '').trim();
      final pkg = (picked['package'] as String? ?? '').trim();
      if (appName.isEmpty || pkg.isEmpty) return;
      final trimmedName = appName.length > 24
          ? appName.substring(0, 24).trim()
          : appName;
      name.text = trimmedName;
      name.selection = TextSelection.collapsed(offset: trimmedName.length);
      setState(() => _selectedPackage = pkg);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'Could not load installed apps.', error: true);
      }
    }
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
      final existingIndex = widget.data.methods.indexWhere(
        (m) => m.toLowerCase() == value.toLowerCase(),
      );
      final canonical = existingIndex >= 0
          ? widget.data.methods[existingIndex]
          : value;
      final methods = existingIndex >= 0
          ? [...widget.data.methods]
          : [...widget.data.methods, value];
      final stored = [...walletStoredOrder(widget.data.prefs)]
        ..removeWhere((m) => m.toLowerCase() == canonical.toLowerCase());
      final order = [...stored, canonical];
      final db = ref.read(databaseProvider);
      final pkg = _selectedPackage;
      await db.transaction(() async {
        final fresh = await db.readAll();
        final hidden = {...fresh.hiddenWallets}
          ..remove(canonical.toLowerCase());
        await db.pref('methods', jsonEncode(methods));
        await db.pref('hiddenWallets', jsonEncode(hidden.toList()));
        await db.pref('walletOrder', jsonEncode(order));
        await db.pref(
          'wallet:$canonical:style',
          WalletSkin.byName(canonical).id,
        );
        if (pkg != null && pkg.isNotEmpty) {
          await db.pref('wallet:$canonical:package', pkg);
          final config = AutomationSync.config(fresh);
          final apps = Set<String>.from(config['apps'] as List? ?? []);
          apps.add(pkg);
          config['apps'] = apps.toList();
          await db.pref('automation', jsonEncode(config));
          await db.pref('purchaseScanning', true);
        }
      });
      if (pkg != null && pkg.isNotEmpty) {
        await AutomationSync.configure(await db.readAll());
        if (mounted) {
          await PermissionHints.request<bool>(
            context,
            'notificationPermission',
          );
        }
      }
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
  Widget build(BuildContext c) {
    final suggestions = _methodSuggestions();
    return PanelContent(
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _pickInstalledApp,
                  icon: const Icon(LucideIcons.smartphone, size: 16),
                  label: Text(
                    _selectedPackage == null
                        ? 'Pick installed app'
                        : 'App: $_selectedPackage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_selectedPackage != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Clear linked app',
                  onPressed: busy
                      ? null
                      : () => setState(() => _selectedPackage = null),
                  icon: const Icon(LucideIcons.x, size: 16),
                ),
              ],
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Select payment method',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final item in suggestions)
                  ActionChip(
                    label: Text(item),
                    onPressed: busy
                        ? null
                        : () {
                            name.text = item;
                            name.selection = TextSelection.collapsed(
                              offset: item.length,
                            );
                            setState(() => _selectedPackage = null);
                          },
                  ),
              ],
            ),
          ],
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
}

class WalletTransferSheet extends ConsumerStatefulWidget {
  final AppData data;
  final String? initialFrom;
  final String? initialTo;
  final String? initialDay;
  final String? existingOccurrence;
  const WalletTransferSheet({
    super.key,
    required this.data,
    this.initialFrom,
    this.initialTo,
    this.initialDay,
    this.existingOccurrence,
  });

  @override
  ConsumerState<WalletTransferSheet> createState() =>
      _WalletTransferSheetState();
}

class _WalletTransferSheetState extends ConsumerState<WalletTransferSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _from;
  late String _to;
  late String _day;
  double _swapTurns = 0;
  bool _busy = false;

  bool get _isEdit => widget.existingOccurrence != null;

  @override
  void initState() {
    super.initState();
    final names = widget.data.orderedWalletNames(
      walletStoredOrder(widget.data.prefs),
    );
    Entry? outLeg;
    Entry? inLeg;
    final targetPrefix = AppDatabase.transferPrefix(widget.existingOccurrence);
    if (targetPrefix != null) {
      for (final e in widget.data.entries) {
        if (AppDatabase.transferPrefix(e.occurrence) != targetPrefix) continue;
        if (e.kind == 'transfer_out') outLeg ??= e;
        if (e.kind == 'transfer_in') inLeg ??= e;
      }
    }
    _day =
        outLeg?.day ??
        inLeg?.day ??
        widget.initialDay ??
        dayKey(DateTime.now());
    _from =
        outLeg?.method ??
        widget.initialFrom ??
        (names.isNotEmpty ? names.first : 'Cash');
    _to =
        inLeg?.method ??
        widget.initialTo ??
        names.firstWhere(
          (n) => n.toLowerCase() != _from.toLowerCase(),
          orElse: () => names.length > 1 ? names[1] : _from,
        );
    if (_from.toLowerCase() == _to.toLowerCase() && names.length > 1) {
      _to = names.firstWhere(
        (n) => n.toLowerCase() != _from.toLowerCase(),
        orElse: () => _to,
      );
    }
    final seedAmount = outLeg?.amount ?? inLeg?.amount ?? 0;
    _amount = TextEditingController(
      text: seedAmount > 0
          ? editableMoney(seedAmount, widget.data.currency)
          : '',
    );
    _note = TextEditingController(text: outLeg?.note ?? inLeg?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int _typedMinor() {
    try {
      final raw = _amount.text.trim();
      if (raw.isEmpty) return 0;
      return parseMoney(raw, widget.data.currency);
    } catch (_) {
      return 0;
    }
  }

  void _swap() {
    if (_busy || _from == _to) return;
    HapticFeedback.selectionClick();
    setState(() {
      final prevFrom = _from;
      _from = _to;
      _to = prevFrom;
      _swapTurns += 0.5;
    });
  }

  Future<void> _pickWallet({required bool isFrom}) async {
    if (_busy) return;
    final accounts = walletAccounts(widget.data);
    final current = isFrom ? _from : _to;
    final picked = await panel<String>(
      context,
      PanelContent(
        header: PanelHeading(title: isFrom ? 'Transfer from' : 'Transfer to'),
        footer: AppButton(
          label: 'Cancel',
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
        child: Column(
          children: [
            for (final a in accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _WalletMark(account: a, size: 36),
                title: Text(a.name),
                subtitle: Text(
                  money(a.balance, widget.data.currency),
                  style: const TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 11,
                  ),
                ),
                trailing: a.name.toLowerCase() == current.toLowerCase()
                    ? const Icon(LucideIcons.check, size: 18)
                    : null,
                onTap: () => Navigator.pop(context, a.name),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (isFrom) {
        if (picked.toLowerCase() == _to.toLowerCase()) {
          _to = _from;
          _swapTurns += 0.5;
        }
        _from = picked;
      } else {
        if (picked.toLowerCase() == _from.toLowerCase()) {
          _from = _to;
          _swapTurns += 0.5;
        }
        _to = picked;
      }
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: calendarDate(_day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = dayKey(picked));
  }

  Future<void> _submit() async {
    if (_busy) return;
    try {
      final minor = parseMoney(_amount.text, widget.data.currency);
      if (minor <= 0) {
        throw const FormatException('Enter an amount greater than zero.');
      }
      if (_from.toLowerCase() == _to.toLowerCase()) {
        throw const FormatException('Choose two different wallets.');
      }
      setState(() => _busy = true);
      final db = ref.read(databaseProvider);
      await db.saveTransfer(
        day: _day,
        amount: minor,
        currency: widget.data.currency,
        fromMethod: _from,
        toMethod: _to,
        note: _note.text.trim(),
        existingOccurrence: widget.existingOccurrence,
      );
      if (mounted) {
        dataToast(
          context,
          'Transfer',
          _isEdit ? DataAction.updated : DataAction.saved,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is FormatException
              ? e.message
              : 'Could not save transfer. Try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final occ = widget.existingOccurrence;
    if (occ == null || _busy) return;
    if (!await confirm(
      context,
      'Delete transfer?',
      'Both the outgoing and incoming wallet entries will be removed.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).deleteTransfer(occ);
      if (mounted) {
        dataToast(context, 'Transfer', DataAction.deleted);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        toast(context, 'Could not delete transfer. Try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final accounts = walletAccounts(widget.data);
    WalletAccount findAccount(String name) => accounts.firstWhere(
      (a) => a.name.toLowerCase() == name.toLowerCase(),
      orElse: () => WalletAccount(
        name: name,
        balance: widget.data.walletBalance(name),
        skin: WalletSkin.byName(name),
        imagePath: null,
        scale: 1,
        dx: 0,
        dy: 0,
        included: true,
        movements: 0,
      ),
    );
    final fromAccount = findAccount(_from);
    final toAccount = findAccount(_to);
    final currency = widget.data.currency;
    final dur = Motion.duration(c, 220);

    return PanelContent(
      header: PanelHeading(
        title: _isEdit ? 'Edit transfer' : 'Transfer money',
        leading: Chrome(
          padding: const EdgeInsets.all(10),
          child: const Icon(LucideIcons.arrowLeftRight, size: 20),
        ),
      ),
      footer: PanelActions(
        children: [
          AppButton(
            label: _isEdit ? 'Save transfer' : 'Transfer',
            icon: LucideIcons.arrowLeftRight,
            busy: _busy,
            onPressed: _submit,
          ),
          if (_isEdit)
            AppButton(
              label: 'Delete transfer',
              secondary: true,
              destructive: true,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _amount,
        builder: (c, _, _) {
          final delta = _typedMinor();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: dur,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.96,
                            end: 1,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _TransferWalletTile(
                        key: ValueKey('from-$_from'),
                        role: 'FROM',
                        account: fromAccount,
                        delta: -delta,
                        currency: currency,
                        onTap: () => _pickWallet(isFrom: true),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Swap source and destination wallets',
                        child: Chrome(
                          padding: EdgeInsets.zero,
                          child: IconButton(
                            tooltip: 'Swap wallets',
                            onPressed: _busy ? null : _swap,
                            icon: AnimatedRotation(
                              turns: MediaQuery.disableAnimationsOf(c)
                                  ? 0
                                  : _swapTurns,
                              duration: Motion.duration(c, 260),
                              curve: Curves.easeOutCubic,
                              child: const Icon(
                                LucideIcons.arrowLeftRight,
                                size: 17,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: dur,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.96,
                            end: 1,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _TransferWalletTile(
                        key: ValueKey('to-$_to'),
                        role: 'TO',
                        account: toAccount,
                        delta: delta,
                        currency: currency,
                        onTap: () => _pickWallet(isFrom: false),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                autofocus: !_isEdit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount ($currency)',
                  prefixText: '${moneySymbol(currency)} ',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (fromAccount.balance > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final ratio in const [
                      ('25%', 0.25),
                      ('50%', 0.5),
                      ('All', 1.0),
                    ])
                      ActionChip(
                        label: Text(ratio.$1),
                        onPressed: _busy
                            ? null
                            : () {
                                final target = (fromAccount.balance * ratio.$2)
                                    .round();
                                if (target <= 0) return;
                                final text = editableMoney(target, currency);
                                _amount.value = TextEditingValue(
                                  text: text,
                                  selection: TextSelection.collapsed(
                                    offset: text.length,
                                  ),
                                );
                              },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.calendar, size: 18),
                title: const Text('Date'),
                subtitle: Text(
                  DateFormat('EEEE, d MMMM yyyy').format(calendarDate(_day)),
                ),
                onTap: _busy ? null : _pickDay,
              ),
              TextField(
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Cash-in, savings top-up',
                  counterText: '',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransferWalletTile extends StatelessWidget {
  final String role;
  final WalletAccount account;
  final int delta;
  final String currency;
  final VoidCallback onTap;
  const _TransferWalletTile({
    super.key,
    required this.role,
    required this.account,
    required this.delta,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final nextBalance = account.balance + delta;
    final overdraft = role == 'FROM' && delta != 0 && nextBalance < 0;
    final positive = role == 'TO' && delta > 0;
    final previewColor = overdraft
        ? theme.colorScheme.error
        : positive
        ? const Color(0xFF2E7D32)
        : theme.colorScheme.onSurfaceVariant;
    return Surface(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    role,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _WalletMark(account: account, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: Motion.duration(c, 160),
                  child: Text(
                    delta == 0
                        ? money(account.balance, currency)
                        : money(nextBalance, currency),
                    key: ValueKey(
                      '$role-${delta == 0 ? account.balance : nextBalance}',
                    ),
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: delta == 0
                          ? theme.colorScheme.onSurface
                          : previewColor,
                    ),
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
