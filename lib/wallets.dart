part of 'screens.dart';

/// Display preference for the wallet cards on Finance.
enum WalletView {
  rows('rows', 'Rows', LucideIcons.rows),
  grid('grid', 'Multi', LucideIcons.layoutGrid),
  stack('stack', 'Stack', LucideIcons.layers);

  const WalletView(this.id, this.label, this.icon);
  final String id, label;
  final IconData icon;

  static WalletView restore(String? value) {
    for (final view in values) {
      if (view.id == value) return view;
    }
    return WalletView.grid;
  }
}

enum WalletPattern { rings, wave, ribbon, grid, arcs, stripes, glow }

/// Built-in card artwork. Presets are painted, not bundled bank artwork, so
/// cards stay sharp at every size and never depend on a remote asset.
class WalletSkin {
  final String id, label, network;
  final List<Color> colors;
  final Color ink, accent;
  final WalletPattern pattern;
  final bool dark;
  final String? assetPath;
  const WalletSkin({
    required this.id,
    required this.label,
    required this.colors,
    required this.ink,
    required this.accent,
    required this.pattern,
    this.network = 'none',
    this.dark = true,
    this.assetPath,
  });

  static const presets = <WalletSkin>[
    WalletSkin(
      id: 'gcash',
      label: 'GCash',
      colors: [Color(0xff0758c9), Color(0xff48b8ff)],
      ink: Colors.white,
      accent: Colors.white,
      pattern: WalletPattern.rings,
      network: 'visa',
      assetPath: 'assets/wallet-cards/gcash.png',
    ),
    WalletSkin(
      id: 'maya',
      label: 'Maya',
      colors: [Color(0xff07080a), Color(0xff101316)],
      ink: Colors.white,
      accent: Color(0xff2cf498),
      pattern: WalletPattern.wave,
      network: 'none',
      assetPath: 'assets/wallet-cards/maya.png',
    ),
    WalletSkin(
      id: 'maribank',
      label: 'MariBank',
      colors: [Color(0xffff4800), Color(0xffff6314)],
      ink: Colors.white,
      accent: Colors.white,
      pattern: WalletPattern.wave,
      network: 'none',
      assetPath: 'assets/wallet-cards/maribank.png',
    ),
    WalletSkin(
      id: 'gotyme',
      label: 'GoTyme',
      colors: [Color(0xff061317), Color(0xff00bce0)],
      ink: Colors.white,
      accent: Color(0xff00e5ff),
      pattern: WalletPattern.stripes,
      network: 'none',
      assetPath: 'assets/wallet-cards/gotyme.png',
    ),
    WalletSkin(
      id: 'gotyme_fifa',
      label: 'GoTyme FIFA 26',
      colors: [Color(0xff050607), Color(0xff181b20)],
      ink: Colors.white,
      accent: Color(0xffd4af37),
      pattern: WalletPattern.glow,
      network: 'none',
      assetPath: 'assets/wallet-cards/gotyme_fifa.png',
    ),
    WalletSkin(
      id: 'hellomoney',
      label: 'HelloMoney',
      colors: [Color(0xffed120a), Color(0xffff3b30)],
      ink: Colors.white,
      accent: Color(0xffffd84d),
      pattern: WalletPattern.arcs,
      network: 'none',
      assetPath: 'assets/wallet-cards/hellomoney.png',
    ),
    WalletSkin(
      id: 'bpi',
      label: 'BPI',
      colors: [Color(0xffb3131b), Color(0xff5e0008)],
      ink: Colors.white,
      accent: Color(0xffffd27a),
      pattern: WalletPattern.ribbon,
      network: 'mastercard',
    ),
    WalletSkin(
      id: 'metrobank',
      label: 'Metrobank',
      colors: [Color(0xff002f96), Color(0xff2f7dff)],
      ink: Colors.white,
      accent: Colors.white,
      pattern: WalletPattern.wave,
      network: 'mastercard',
    ),
    WalletSkin(
      id: 'rcbc',
      label: 'RCBC',
      colors: [Color(0xff00254f), Color(0xff0076c8)],
      ink: Colors.white,
      accent: Color(0xff6fd3ff),
      pattern: WalletPattern.grid,
      network: 'mastercard',
    ),
    WalletSkin(
      id: 'bdo',
      label: 'BDO',
      colors: [Color(0xffc99a3b), Color(0xff7e5310)],
      ink: Colors.white,
      accent: Color(0xffffe2a1),
      pattern: WalletPattern.arcs,
      network: 'mastercard',
    ),
    WalletSkin(
      id: 'shopeepay',
      label: 'ShopeePay',
      colors: [Color(0xffe83a1b), Color(0xffff8a3d)],
      ink: Colors.white,
      accent: Colors.white,
      pattern: WalletPattern.stripes,
      network: 'visa',
    ),
    WalletSkin(
      id: 'paypal',
      label: 'PayPal',
      colors: [Color(0xff002d7a), Color(0xff0b4ed2)],
      ink: Colors.white,
      accent: Color(0xff8cc4ff),
      pattern: WalletPattern.rings,
      network: 'visa',
    ),
    WalletSkin(
      id: 'wise',
      label: 'Wise',
      colors: [Color(0xffa6ef6e), Color(0xff43b93d)],
      ink: Color(0xff103015),
      accent: Colors.white,
      pattern: WalletPattern.arcs,
      network: 'visa',
      dark: false,
    ),
    WalletSkin(
      id: 'atome',
      label: 'Atome',
      colors: [Color(0xffffe7f1), Color(0xffc4ebff), Color(0xffe8d7ff)],
      ink: Color(0xff20212a),
      accent: Colors.white,
      pattern: WalletPattern.ribbon,
      network: 'mastercard',
      dark: false,
    ),
    WalletSkin(
      id: 'unionbank',
      label: 'UnionBank',
      colors: [Color(0xff191919), Color(0xff4b3924)],
      ink: Colors.white,
      accent: Color(0xffffcf8a),
      pattern: WalletPattern.wave,
      network: 'visa',
    ),
    WalletSkin(
      id: 'cash',
      label: 'Cash',
      colors: [Color(0xff133829), Color(0xff2d6e52)],
      ink: Colors.white,
      accent: Color(0xffffe699),
      pattern: WalletPattern.glow,
      network: 'none',
      assetPath: 'assets/wallet-cards/cash.png',
    ),
    WalletSkin(
      id: 'bank',
      label: 'Bank',
      colors: [Color(0xff33454d), Color(0xff8199a1)],
      ink: Colors.white,
      accent: Color(0xffd8f1ff),
      pattern: WalletPattern.grid,
      network: 'none',
    ),
    WalletSkin(
      id: 'card',
      label: 'Card',
      colors: [Color(0xff242628), Color(0xff4a4f52)],
      ink: Colors.white,
      accent: Color(0xffffd27a),
      pattern: WalletPattern.stripes,
      network: 'mastercard',
    ),
    WalletSkin(
      id: 'ink',
      label: 'Ink',
      colors: [Color(0xff1b1d1b), Color(0xff343a35)],
      ink: Colors.white,
      accent: Color(0xffc5d6c4),
      pattern: WalletPattern.glow,
      network: 'none',
    ),
  ];

  static WalletSkin byId(String id) =>
      presets.firstWhere((skin) => skin.id == id, orElse: () => presets.last);

  /// Stored artwork wins; otherwise the method name picks a familiar palette.
  static WalletSkin resolve(String method, String? stored) {
    if (stored != null && stored != 'custom') {
      for (final skin in presets) {
        if (skin.id == stored) return skin;
      }
    }
    return byName(method);
  }

  static WalletSkin byName(String method) {
    final name = method.toLowerCase();
    if (name.contains('gcash') || name.contains('g cash')) {
      return byId('gcash');
    }
    if (name.contains('maya')) return byId('maya');
    if (name.contains('maribank') ||
        name.contains('mari bank') ||
        name.contains('seabank')) {
      return byId('maribank');
    }
    if (name.contains('gotyme') || name.contains('go tyme')) {
      return byId('gotyme');
    }
    if (name.contains('hellomoney') ||
        name.contains('hello money') ||
        name.contains('aub')) {
      return byId('hellomoney');
    }
    if (name.contains('bpi')) return byId('bpi');
    if (name.contains('metro')) return byId('metrobank');
    if (name.contains('rcbc')) return byId('rcbc');
    if (name.contains('bdo')) return byId('bdo');
    if (name.contains('shopee')) return byId('shopeepay');
    if (name.contains('paypal')) return byId('paypal');
    if (name.contains('wise')) return byId('wise');
    if (name.contains('atome')) return byId('atome');
    if (name.contains('union')) return byId('unionbank');
    if (name.contains('cash')) return byId('cash');
    if (name.contains('bank')) return byId('bank');
    if (name.contains('card') || name.contains('credit')) return byId('card');
    return byId('ink');
  }
}

class WalletAccount {
  final String name;
  final int balance;
  final WalletSkin skin;
  final String? imagePath;
  final double scale, dx, dy;
  final bool included;
  final int movements;
  final String? packageName;

  /// Planned money that still leaves this wallet in the selected month.
  final int committed;
  const WalletAccount({
    required this.name,
    required this.balance,
    required this.skin,
    required this.imagePath,
    required this.scale,
    required this.dx,
    required this.dy,
    required this.included,
    required this.movements,
    this.packageName,
    this.committed = 0,
  });

  bool get hasCustomArtwork =>
      imagePath != null && File(imagePath!).existsSync();
}

List<String> walletStoredOrder(Map<String, String> prefs) {
  try {
    final decoded = jsonDecode(prefs['walletOrder'] ?? '[]');
    if (decoded is List) {
      return decoded.whereType<String>().toList();
    }
  } catch (_) {}
  return const [];
}

List<WalletAccount> walletAccounts(
  AppData data, [
  List<String>? ordered,
  Map<String, int> committed = const {},
]) {
  final names =
      ordered ?? data.orderedWalletNames(walletStoredOrder(data.prefs));
  final balances = data.walletBalances;
  final canonicalByLower = <String, String>{
    for (final name in names) name.toLowerCase(): name,
  };
  final movements = <String, int>{};
  for (final entry in data.entries) {
    if (entry.currency != data.currency) continue;
    final raw = walletMethodName(entry.method);
    final name = canonicalByLower[raw.toLowerCase()] ?? raw;
    movements[name] = (movements[name] ?? 0) + 1;
  }
  return [
    for (final name in names)
      WalletAccount(
        name: name,
        balance: balances[name] ?? 0,
        skin: WalletSkin.resolve(name, data.prefs['wallet:$name:style']),
        imagePath: data.prefs['wallet:$name:style'] == 'custom'
            ? data.prefs['wallet:$name:image']
            : null,
        scale: double.tryParse(data.prefs['wallet:$name:scale'] ?? '') ?? 1,
        dx: double.tryParse(data.prefs['wallet:$name:dx'] ?? '') ?? 0,
        dy: double.tryParse(data.prefs['wallet:$name:dy'] ?? '') ?? 0,
        included: data.prefs['wallet:$name:include'] != 'false',
        movements: movements[name] ?? 0,
        packageName: data.prefs['wallet:$name:package'],
        committed: committed[name] ?? 0,
      ),
  ];
}

/// Everything the Unified Financial Overview needs for one month and wallet scope.
class FinanceMonth {
  final DateTime period;
  final int opening,
      income,
      expenses,
      savings,
      transferNet,
      net,
      closing,
      available,
      safe,
      commitments;
  final double used;
  const FinanceMonth({
    required this.period,
    this.opening = 0,
    required this.income,
    required this.expenses,
    required this.savings,
    this.transferNet = 0,
    required this.net,
    this.closing = 0,
    this.available = 0,
    required this.safe,
    required this.commitments,
    required this.used,
  });
}

FinanceMonth financeMonth(
  AppData data,
  DateTime period,
  String? wallet,
  List<Projection> planned,
) {
  final monthPrefix = dayKey(period).substring(0, 7);
  final eligibleEntries = data.scopedEntries(wallet: wallet);
  var opening = 0;
  var income = 0;
  var expenses = 0;
  var savings = 0;
  var transfersIn = 0;
  var transfersOut = 0;
  var available = 0;

  for (final e in eligibleEntries) {
    final delta = AppData.entryBalanceDelta(e);
    available += delta;
    final entryMonth = e.day.length >= 7 ? e.day.substring(0, 7) : e.day;
    final cmp = entryMonth.compareTo(monthPrefix);
    if (cmp < 0) {
      opening += delta;
    } else if (cmp == 0) {
      switch (e.kind) {
        case 'income':
          income += e.amount;
        case 'expense':
          expenses += e.amount;
        case 'savings':
          savings += e.amount;
        case 'transfer_in':
          transfersIn += e.amount;
        case 'transfer_out':
          transfersOut += e.amount;
      }
    }
  }

  final transferNet = transfersIn - transfersOut;
  final net = income - expenses - savings + transferNet;
  final closing = opening + net;
  final last = DateTime(period.year, period.month + 1, 0);
  final today = dayKey(DateTime.now());
  final commitments = planned
      .where(
        (p) =>
            p.day.compareTo(today) >= 0 &&
            p.status == 'planned' &&
            p.rule.kind != 'income',
      )
      .fold(0, (sum, p) => sum + p.amount);
  final used = period.isAfter(DateTime.now())
      ? 0.0
      : last.isBefore(DateTime.now())
      ? 1.0
      : DateTime.now().day / last.day;
  return FinanceMonth(
    period: period,
    opening: opening,
    income: income,
    expenses: expenses,
    savings: savings,
    transferNet: transferNet,
    net: net,
    closing: closing,
    available: available,
    safe: math.max(0, closing - commitments),
    commitments: commitments,
    used: used,
  );
}

/// Planned outflows for the selected month, keyed by wallet, for the cards'
/// "planned" line. Includes every wallet even when Finance is scoped.
Map<String, int> walletCommitments(Iterable<Projection> planned) {
  final today = dayKey(DateTime.now());
  final result = <String, int>{};
  for (final p in planned) {
    if (p.status != 'planned' ||
        p.rule.kind == 'income' ||
        p.day.compareTo(today) < 0) {
      continue;
    }
    final name = walletMethodName(p.rule.method);
    result.update(name, (value) => value + p.amount, ifAbsent: () => p.amount);
  }
  return result;
}

String walletMaskedAmount(String currency) => '${moneySymbol(currency)}••••••';

String walletImageFolder() => 'wallet-cards';

Future<File?> pickWalletCardImage() async {
  final picked = await FilePicker.pickFiles(type: FileType.image);
  if (picked.isEmpty) return null;
  final source = picked.first;
  final length = await source.length();
  if (length != null && length > 12 * 1024 * 1024) {
    throw const FormatException('Choose an image under 12 MB.');
  }
  final root = await getApplicationSupportDirectory();
  final folder = Directory('${root.path}/${walletImageFolder()}');
  await folder.create(recursive: true);
  final extension = (source.extension ?? 'jpg').toLowerCase().replaceAll(
    RegExp('[^a-z0-9]'),
    '',
  );
  final target = File(
    '${folder.path}/card-${DateTime.now().microsecondsSinceEpoch}.${extension.isEmpty ? 'jpg' : extension}',
  );
  final path = source.path;
  if (path != null) {
    await File(path).copy(target.path);
  } else {
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
  }
  return target;
}

Future<void> discardWalletCardImage(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (await file.exists() && file.parent.path.endsWith(walletImageFolder())) {
      await file.delete();
    }
  } catch (_) {}
}

class WalletCard extends StatelessWidget {
  final WalletAccount account;
  final String currency;
  final bool masked;
  final bool compact;
  final bool selected;
  final bool showMenu;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenu;
  final String? semanticsLabel;
  const WalletCard({
    super.key,
    required this.account,
    required this.currency,
    required this.masked,
    this.compact = false,
    this.selected = false,
    this.showMenu = true,
    this.onTap,
    this.onLongPress,
    this.onMenu,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext c) {
    final theme = Theme.of(c);
    final border = BorderRadius.circular(compact ? 13 : 18);
    final art = AspectRatio(
      aspectRatio: 1.586,
      child: ClipRRect(
        borderRadius: border,
        child: LayoutBuilder(
          builder: (c, constraints) {
            final width = constraints.maxWidth;
            final height = width / 1.586;
            final f = (width / 180).clamp(.74, 1.38);
            final pad = 12.0 * f;
            final ink = account.skin.ink;
            final hasImage =
                account.hasCustomArtwork || account.skin.assetPath != null;
            final amount = masked
                ? walletMaskedAmount(currency)
                : money(account.balance, currency);
            return Stack(
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
                  Positioned.fill(
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(account.dx * width, account.dy * height),
                        child: Transform.scale(
                          scale: account.scale.clamp(1, 4),
                          child: Image.file(
                            File(account.imagePath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (account.skin.assetPath != null)
                  Positioned.fill(
                    child: Image.asset(
                      account.skin.assetPath!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => CustomPaint(
                        painter: _WalletPatternPainter(account.skin),
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _WalletPatternPainter(account.skin),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: account.skin.dark
                            ? [
                                Colors.black.withValues(alpha: .18),
                                Colors.transparent,
                                Colors.black.withValues(alpha: .54),
                              ]
                            : [
                                Colors.white.withValues(alpha: .18),
                                Colors.transparent,
                                Colors.white.withValues(alpha: .55),
                              ],
                        stops: const [0, .42, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: pad,
                  right: pad,
                  top: pad,
                  child: Row(
                    children: [
                      if (!hasImage) ...[
                        _WalletChip(scale: f, dark: account.skin.dark),
                        SizedBox(width: 7 * f),
                      ],
                      Expanded(
                        child: hasImage
                            ? const SizedBox.shrink()
                            : Text(
                                account.name.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 10.5 * f,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1 * f,
                                ),
                              ),
                      ),
                      if (showMenu)
                        Semantics(
                          button: true,
                          label: '${account.name} card options',
                          child: InkResponse(
                            onTap: onMenu,
                            radius: 18 * f,
                            child: Container(
                              width: 24 * f,
                              height: 24 * f,
                              decoration: BoxDecoration(
                                color:
                                    (account.skin.dark
                                            ? Colors.black
                                            : Colors.white)
                                        .withValues(alpha: .24),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.ellipsis,
                                size: 14 * f,
                                color: ink,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: pad,
                  right: pad,
                  bottom: pad,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.included
                                  ? 'BALANCE'
                                  : 'BALANCE · EXCLUDED',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink.withValues(alpha: .78),
                                fontSize: 7.5 * f,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5 * f,
                              ),
                            ),
                            SizedBox(height: 4 * f),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                amount,
                                style: TextStyle(
                                  color: ink,
                                  fontFamily: 'Geist Mono',
                                  fontSize: 13 * f,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.2 * f,
                                ),
                              ),
                            ),
                            if (account.committed > 0) ...[
                              SizedBox(height: 3 * f),
                              Text(
                                masked
                                    ? 'Planned'
                                    : '${money(account.committed, currency)} planned',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink.withValues(alpha: .8),
                                  fontFamily: 'Geist Mono',
                                  fontSize: 7 * f,
                                  height: 1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!hasImage)
                        _WalletNetwork(
                          network: account.skin.network,
                          color: ink,
                          scale: f,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    final card = onTap == null && onLongPress == null
        ? art
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: border,
              onTap: onTap,
              onLongPress: onLongPress,
              child: art,
            ),
          );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticsLabel,
      child: selected
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: border,
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: card,
            )
          : card,
    );
  }
}

class _WalletChip extends StatelessWidget {
  final double scale;
  final bool dark;
  const _WalletChip({required this.scale, required this.dark});

  @override
  Widget build(BuildContext c) {
    final width = 25 * scale;
    final height = 17 * scale;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4 * scale),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffffecb2), Color(0xffc49033)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: .5),
          width: .7 * scale,
        ),
      ),
      child: CustomPaint(painter: _ChipPainter(scale)),
    );
  }
}

class _ChipPainter extends CustomPainter {
  final double scale;
  const _ChipPainter(this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff7b5518).withValues(alpha: .5)
      ..strokeWidth = .8 * scale;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(w * .28, h * .18), Offset(w * .28, h * .82), paint);
    canvas.drawLine(Offset(w * .62, h * .18), Offset(w * .62, h * .82), paint);
    canvas.drawLine(Offset(w * .1, h * .5), Offset(w * .9, h * .5), paint);
  }

  @override
  bool shouldRepaint(covariant _ChipPainter old) => old.scale != scale;
}

const String _visaSvg = r"""<svg width="250" height="65" viewBox="0 0 250 65" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M113 35.3906C113 35.4986 113 35.5525 113 35.6605C112.836 35.6605 112.673 35.6605 112.509 35.6605C109.999 35.6605 107.489 35.6605 104.979 35.6605C104.652 35.6605 104.488 35.5525 104.434 35.2287C104.161 33.7176 103.833 32.2604 103.506 30.7492C103.451 30.4793 103.342 30.3714 103.07 30.3714C99.4138 30.3714 95.7581 30.3714 92.1024 30.3714C91.775 30.3714 91.6659 30.4793 91.5567 30.7492C91.0111 32.2604 90.4655 33.7715 89.9199 35.2827C89.8107 35.5525 89.7016 35.6605 89.3742 35.6605C86.4278 35.6605 83.536 35.6605 80.5896 35.6605C80.4805 35.6605 80.3168 35.7145 80.2076 35.6065C80.2622 35.4446 80.3168 35.3367 80.3713 35.2287C83.6997 27.403 86.9735 19.5774 90.3018 11.7517C91.5022 8.94525 92.648 6.13881 93.8484 3.38633C94.394 2.09104 95.3762 1.17355 96.7948 0.849731C97.3404 0.74179 97.8861 0.63385 98.4317 0.63385C100.723 0.63385 103.015 0.63385 105.252 0.63385C105.525 0.63385 105.634 0.68782 105.689 0.957671C106.452 4.62764 107.216 8.29761 107.98 11.9676C109.399 18.7139 110.817 25.5141 112.291 32.2604C112.509 33.2858 112.673 34.3652 113 35.3906ZM99.1956 10.1326C99.141 10.2405 99.0864 10.2405 99.0864 10.2945C97.5587 14.4502 95.9764 18.6599 94.4486 22.8156C94.3395 23.1934 94.5032 23.1394 94.7214 23.1394C96.9585 23.1394 99.2501 23.1394 101.487 23.1394C101.815 23.1394 101.869 23.0854 101.815 22.7616C100.942 18.6059 100.069 14.3962 99.1956 10.1326Z" fill="#01579F"/>
<path d="M77.4249 0.202082C78.8981 0.471933 80.3713 0.795754 81.7899 1.33546C82.0627 1.4434 82.0627 1.55134 82.0627 1.76722C81.6808 4.08793 81.2988 6.40865 80.9169 8.72937C80.8623 9.10716 80.6441 8.89128 80.535 8.83731C78.9526 8.13569 77.3703 7.59599 75.6789 7.43408C73.8237 7.2182 71.9686 7.16423 70.168 7.81187C69.5678 8.02775 69.0222 8.35157 68.5857 8.83731C67.7672 9.7548 67.7672 10.8882 68.5857 11.8057C69.1859 12.4533 69.8952 12.939 70.7136 13.3708C72.0777 14.1264 73.4418 14.774 74.8058 15.5296C76.2791 16.3392 77.5886 17.3106 78.7344 18.5519C80.535 20.6028 81.1352 22.9775 80.7532 25.622C80.0439 30.4793 76.9884 33.3398 72.5142 34.9589C70.0043 35.8764 67.3307 36.1462 64.6571 36.1462C64.4934 36.1462 62.7474 36.0922 62.2564 36.0383C59.801 35.7684 57.4548 35.3906 55.1632 34.4731C54.8358 34.3652 54.7267 34.2033 54.7812 33.8255C55.1632 31.5048 55.5451 29.1841 55.927 26.9173C55.9816 26.4316 55.9816 26.4316 56.4727 26.6475C58.4369 27.565 60.4012 28.3745 62.5292 28.6444C64.4389 28.8602 66.3486 29.0761 68.2583 28.5364C69.0767 28.3205 69.786 27.9427 70.3862 27.403C71.4775 26.3776 71.5321 24.8664 70.5499 23.7331C69.7861 22.8695 68.7494 22.2759 67.7127 21.7362C66.1849 20.9266 64.6571 20.225 63.2385 19.3075C61.929 18.39 60.7286 17.4186 59.801 16.0693C58.055 13.4787 58.1096 10.7263 59.1463 7.91981C60.2375 5.0594 62.42 3.17044 65.1482 1.82119C67.2216 0.795754 69.4587 0.202082 71.8049 0.0941419C73.2781 -0.0677685 76.0608 -0.0137984 77.4249 0.202082Z" fill="#01579F"/>
<path d="M0 1.06564C0.054563 0.57991 0.381941 0.52594 0.818445 0.52594C5.40174 0.52594 9.98503 0.52594 14.5683 0.52594C15.0594 0.52594 15.605 0.57991 16.0961 0.68785C17.7875 1.01167 18.7697 1.98313 19.0971 3.65621C20.0792 8.67543 21.1159 13.6947 22.098 18.7139C22.1526 18.8758 22.2071 19.1996 22.2071 19.3615C22.2071 19.3076 22.098 19.0917 22.0435 19.0377C19.6972 13.2089 15.6596 8.78337 10.2578 5.49119C10.0942 5.38325 9.49397 5.05943 9.38484 5.00546C6.493 3.38636 3.49203 2.19901 0.272815 1.38946C0.163689 1.33549 0 1.28152 0 1.28152C0 1.17358 0 1.17358 0 1.06564Z" fill="#01579F"/>
<path d="M9.60315 5.11339C9.87596 5.2753 10.0397 5.38324 10.2579 5.49118C15.6051 8.78336 19.6427 13.2089 22.0435 19.0377C22.0435 19.0917 22.1526 19.2536 22.2072 19.3615C22.5346 20.9266 22.862 22.4918 23.1893 24.1109C23.1893 24.1649 23.1893 24.2728 23.2985 24.3268C23.4076 24.0029 23.5713 23.6252 23.6804 23.3013C26.4631 15.8534 29.2458 8.40557 32.0831 0.957686C32.1377 0.741805 32.1922 0.579895 32.5196 0.579895C35.6297 0.579895 38.7398 0.579895 41.8499 0.579895C41.9044 0.741805 41.7953 0.849746 41.7953 0.957686C37.1029 12.3994 32.4105 23.841 27.7181 35.2287C27.6089 35.4986 27.4998 35.5526 27.227 35.5526C24.226 35.5526 21.2796 35.5526 18.2787 35.5526C18.0059 35.5526 17.8967 35.4446 17.7876 35.1748C15.0594 25.4062 12.4404 15.5836 9.8214 5.76103C9.76684 5.59912 9.65771 5.2753 9.60315 5.11339Z" fill="#01579F"/>
<path d="M44.3598 35.6065C42.9411 35.6065 41.577 35.6065 40.1584 35.6065C39.8856 35.6065 39.7765 35.5526 39.831 35.2287C41.0314 27.9428 42.2318 20.6028 43.4322 13.3169C44.0869 9.16116 44.7963 5.05943 45.451 0.903731C45.5056 0.63388 45.6147 0.52594 45.8875 0.52594C48.6702 0.52594 51.4529 0.52594 54.2902 0.52594C54.6176 0.52594 54.6722 0.63388 54.6176 0.903731C54.072 4.46576 53.4718 7.91985 52.9261 11.4279C52.2714 15.2598 51.6712 19.1456 51.0164 22.9775C50.3617 26.8634 49.7615 30.7492 49.1067 34.6351C48.943 35.6065 48.943 35.6065 47.9064 35.6065C46.7605 35.6065 45.5601 35.6065 44.3598 35.6065Z" fill="#01579F"/>
</svg>""";
const String _mastercardSvg = r"""<svg width="250" height="65" viewBox="0 0 250 65" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M50.359 5.23816H28.9215V43.762H50.359V5.23816Z" fill="#FF5F00"/>
<path d="M30.2827 24.5C30.2794 20.7899 31.1201 17.1276 32.7413 13.7905C34.3625 10.4533 36.7217 7.52871 39.6403 5.23811C36.0261 2.39722 31.6854 0.63052 27.1146 0.139926C22.5437 -0.350668 17.927 0.454626 13.7922 2.4638C9.65742 4.47297 6.1713 7.60496 3.73234 11.5017C1.29338 15.3985 0 19.9029 0 24.5C0 29.0971 1.29338 33.6015 3.73234 37.4983C6.1713 41.395 9.65742 44.527 13.7922 46.5362C17.927 48.5454 22.5437 49.3507 27.1146 48.8601C31.6854 48.3695 36.0261 46.6028 39.6403 43.7619C36.7217 41.4713 34.3626 38.5467 32.7413 35.2095C31.1201 31.8724 30.2794 28.2101 30.2827 24.5Z" fill="#EB001B"/>
<path d="M79.2794 24.5C79.2795 29.097 77.9863 33.6014 75.5474 37.4982C73.1086 41.395 69.6226 44.5269 65.4879 46.5361C61.3532 48.5453 56.7365 49.3507 52.1658 48.8601C47.595 48.3695 43.2544 46.6028 39.6403 43.7619C42.5563 41.469 44.9136 38.5439 46.5346 35.2073C48.1555 31.8706 48.9978 28.2095 48.9978 24.5C48.9978 20.7905 48.1555 17.1293 46.5346 13.7927C44.9136 10.4561 42.5563 7.53102 39.6403 5.2381C43.2544 2.39721 47.595 0.630508 52.1658 0.13992C56.7365 -0.350668 61.3532 0.454661 65.4879 2.46386C69.6226 4.47305 73.1086 7.60503 75.5474 11.5018C77.9863 15.3986 79.2795 19.903 79.2794 24.5Z" fill="#F79E1B"/>
<path d="M76.942 39.6816V38.8929H77.26V38.7322H76.4501V38.8929H76.7682V39.6816H76.942ZM78.5144 39.6816V38.7307H78.2661L77.9806 39.3848L77.695 38.7307H77.4465V39.6816H77.6219V38.9643L77.8896 39.5827H78.0714L78.3392 38.9628V39.6816H78.5144Z" fill="#F79E1B"/>
</svg>""";

class _WalletNetwork extends StatelessWidget {
  final String network;
  final Color color;
  final double scale;
  const _WalletNetwork({
    required this.network,
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext c) {
    if (network == 'none') return const SizedBox.shrink();
    if (network == 'visa') {
      return SvgPicture.string(
        _visaSvg,
        width: 40 * scale,
        height: 10.5 * scale,
        fit: BoxFit.contain,
      );
    }
    return SvgPicture.string(
      _mastercardSvg,
      width: 40 * scale,
      height: 10.5 * scale,
      fit: BoxFit.contain,
    );
  }
}

class _WalletPatternPainter extends CustomPainter {
  final WalletSkin skin;
  const _WalletPatternPainter(this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = skin.accent.withValues(alpha: skin.dark ? .13 : .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .035;
    switch (skin.pattern) {
      case WalletPattern.rings:
        final center = Offset(size.width * .84, size.height * .42);
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(center, size.width * .12 * i, paint);
        }
      case WalletPattern.wave:
        for (var i = 0; i < 3; i++) {
          final path = ui.Path()
            ..moveTo(-size.width * .1, size.height * (.72 + i * .16))
            ..cubicTo(
              size.width * .28,
              size.height * (.35 + i * .13),
              size.width * .55,
              size.height * (1.02 + i * .12),
              size.width * 1.12,
              size.height * (.42 + i * .1),
            );
          canvas.drawPath(path, paint);
        }
      case WalletPattern.ribbon:
        for (var i = 0; i < 4; i++) {
          final x = size.width * (-.1 + i * .28);
          final path = ui.Path()
            ..moveTo(x, size.height)
            ..lineTo(x + size.width * .22, 0);
          canvas.drawPath(path, paint..strokeWidth = size.width * .09);
        }
      case WalletPattern.grid:
        paint.strokeWidth = 1;
        for (var x = 0.0; x < size.width; x += size.width * .13) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y < size.height; y += size.height * .2) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case WalletPattern.arcs:
        paint.strokeWidth = size.width * .05;
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(
            Rect.fromCircle(
              center: Offset(size.width * .95, size.height * .15),
              radius: size.width * (.3 + i * .2),
            ),
            .5,
            2.2,
            false,
            paint,
          );
        }
      case WalletPattern.stripes:
        paint.strokeWidth = size.width * .025;
        for (var x = -size.height; x < size.width; x += size.width * .09) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            paint,
          );
        }
      case WalletPattern.glow:
        final glow = Paint()
          ..shader = RadialGradient(
            colors: [skin.accent.withValues(alpha: .22), Colors.transparent],
          ).createShader(rect);
        canvas.drawRect(rect, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _WalletPatternPainter old) =>
      old.skin.id != skin.id;
}
