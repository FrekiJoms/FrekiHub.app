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
  const WalletSkin({
    required this.id,
    required this.label,
    required this.colors,
    required this.ink,
    required this.accent,
    required this.pattern,
    this.network = 'none',
    this.dark = true,
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
    ),
    WalletSkin(
      id: 'maya',
      label: 'Maya',
      colors: [Color(0xff121112), Color(0xffe3127d)],
      ink: Colors.white,
      accent: Color(0xffffd1e8),
      pattern: WalletPattern.wave,
      network: 'visa',
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
      colors: [Color(0xffc6ad7f), Color(0xff6f5a36)],
      ink: Colors.white,
      accent: Color(0xfffff1c9),
      pattern: WalletPattern.glow,
      network: 'none',
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
  final movements = <String, int>{};
  for (final entry in data.entries) {
    if (entry.currency != data.currency) continue;
    final name = walletMethodName(entry.method);
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
        committed: committed[name] ?? 0,
      ),
  ];
}

/// Everything the Finance header needs for one month and wallet scope.
class FinanceMonth {
  final DateTime period;
  final int income, expenses, savings, net, safe, commitments;
  final double used;
  const FinanceMonth({
    required this.period,
    required this.income,
    required this.expenses,
    required this.savings,
    required this.net,
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
  final month = dayKey(period).substring(0, 7);
  final scoped = data.scopedEntries(wallet: wallet, month: month);
  int total(String kind) =>
      scoped.where((e) => e.kind == kind).fold(0, (sum, e) => sum + e.amount);
  final income = total('income'), expenses = total('expense');
  final savings = total('savings');
  final net = income - expenses - savings;
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
    income: income,
    expenses: expenses,
    savings: savings,
    net: net,
    safe: math.max(0, net - commitments),
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
                      _WalletChip(scale: f, dark: account.skin.dark),
                      SizedBox(width: 7 * f),
                      Expanded(
                        child: Text(
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
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
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
      return Text(
        'VISA',
        style: TextStyle(
          color: color,
          fontSize: 10.5 * scale,
          height: 1,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          letterSpacing: .2 * scale,
        ),
      );
    }
    final size = 12 * scale;
    return SizedBox(
      width: size * 1.6,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xffeb1b2d).withValues(alpha: .9),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xffff9f1c).withValues(alpha: .85),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
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
