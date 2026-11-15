import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'services.dart';
part 'flip_clock.dart';
part 'components.dart';
part 'sheets.dart';
part 'permissions.dart';

abstract final class Motion {
  static const curve = Cubic(.22, 1, .36, 1);
  static const settle = Cubic(.34, 1.36, .64, 1);
  static Duration duration(BuildContext c, [int ms = 250]) =>
      MediaQuery.disableAnimationsOf(c)
      ? Duration.zero
      : Duration(milliseconds: ms);
}

abstract final class Design {
  static const radius = 28.0;
  static const space = 24.0;
  static const chart = [
    Color(0xff8b9d88),
    Color(0xffa8a0ba),
    Color(0xffb9a084),
    Color(0xff839dac),
    Color(0xffbc8b8b),
    Color(0xff9b9b9b),
  ];
  static ThemeData theme(bool dark) {
    final foreground = dark ? const Color(0xfff3f2ef) : const Color(0xff202120);
    final surface = dark ? const Color(0xff222523) : const Color(0xfffcfcfa);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: foreground,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: foreground,
          onPrimary: surface,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: dark
              ? const Color(0xffadb4ae)
              : const Color(0xff616861),
          surfaceContainerLow: dark
              ? const Color(0xff1c201d)
              : const Color(0xfff5f6f2),
          surfaceContainer: dark
              ? const Color(0xff262b27)
              : const Color(0xffeef0ea),
          surfaceContainerHigh: dark
              ? const Color(0xff2c312d)
              : const Color(0xffe8ece4),
          outline: dark ? const Color(0xff738077) : const Color(0xff7b857c),
          outlineVariant: dark
              ? const Color(0xff3c443e)
              : const Color(0xffd9dfd6),
          surfaceContainerHighest: dark
              ? const Color(0xff303331)
              : const Color(0xffe9ebe6),
          error: dark ? const Color(0xffe7a19d) : const Color(0xffac3c35),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Geist',
      scaffoldBackgroundColor: dark
          ? const Color(0xff161917)
          : const Color(0xfff1f2ee),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 56,
          fontWeight: FontWeight.w600,
          letterSpacing: -2.5,
          color: foreground,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.1,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
          color: foreground,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: foreground),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: foreground),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      iconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .3)
              : states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Icon(Icons.check, size: 14, color: scheme.primary)
              : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: .1),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: TextStyle(
          fontFamily: 'Geist Mono',
          fontSize: 12,
          color: scheme.onPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        minVerticalPadding: 12,
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: .45),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: scheme.outlineVariant),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: FloatingDepth.elevation,
        shadowColor: Colors.black.withValues(alpha: dark ? .48 : .28),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
          color: foreground,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.onSurface.withValues(alpha: .18),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: foreground.withValues(alpha: .08),
        space: 28,
      ),
    );
  }
}

class CanvasBackground extends StatelessWidget {
  const CanvasBackground({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.65, -.75),
          radius: 1.6,
          colors: dark
              ? [
                  const Color(0xff323832),
                  const Color(0xff161917),
                  const Color(0xff101211),
                ]
              : [
                  const Color(0xfffbfcf8),
                  const Color(0xffeff1eb),
                  const Color(0xffe1e5de),
                ],
        ),
      ),
      child: CustomPaint(painter: _Grain(dark), child: const SizedBox.expand()),
    );
  }
}

class _Grain extends CustomPainter {
  final bool dark;
  _Grain(this.dark);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .035);
    final random = math.Random(42);
    for (var i = 0; i < s.width * s.height / 100; i++) {
      c.drawCircle(
        Offset(random.nextDouble() * s.width, random.nextDouble() * s.height),
        .45,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Grain old) => dark != old.dark;
}

class Entrance extends StatelessWidget {
  final Widget child;
  final int index;
  const Entrance({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext c) {
    if (MediaQuery.disableAnimationsOf(c) || index > 5) {
      return child;
    }
    return child
        .animate(delay: Duration(milliseconds: math.min(index, 6) * 40))
        .fadeIn(duration: Motion.duration(c, 400), curve: Motion.curve)
        .slideY(
          begin: .025,
          end: 0,
          duration: Motion.duration(c, 400),
          curve: Motion.settle,
        );
  }
}

class SizeTransitionPanel extends StatelessWidget {
  final Widget child;
  final AlignmentGeometry alignment;
  const SizeTransitionPanel({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext c) => MediaQuery.disableAnimationsOf(c)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Motion.curve,
          alignment: alignment,
          child: child,
        );
}

class PageBody extends StatelessWidget {
  final String? title, subtitle;
  final List<Widget> children;
  final Widget? action;
  final bool compactHeader;
  final ScrollController? scrollController;
  final Widget? leading;
  const PageBody({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
    this.action,
    this.compactHeader = false,
    this.scrollController,
    this.leading,
  });
  @override
  Widget build(BuildContext c) => WidthLayoutBuilder(
    builder: (c, width) {
      final inset = width < 380 ? 16.0 : 24.0;
      final horizontal = math.max(inset, (width - 720) / 2);
      final hasHeader =
          (title?.isNotEmpty ?? false) || (subtitle?.isNotEmpty ?? false);
      final header = hasHeader
          ? Entrance(
              child: compactHeader
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 56),
                      child: Column(
                        children: [
                          PageTitle(title ?? ""),
                          const SizedBox(height: 4),
                          Text(
                            subtitle ?? "",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(c).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 56),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subtitle ?? "",
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              ?action,
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        PageTitle(title ?? ""),
                      ],
                    ),
            )
          : const SizedBox.shrink();
      final bottomPad = 126 + MediaQuery.paddingOf(c).bottom;
      final content = <Widget>[
        if (leading != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: leading),
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Entrance(index: i + 1, child: children[i]),
          ),
        KeyboardScrollSpacer(baseBottom: bottomPad),
      ];
      if (compactHeader) {
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
              child: header,
            ),
            Expanded(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) =>
                    const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.white],
                    ).createShader(
                      Rect.fromLTWH(bounds.left, bounds.top, bounds.width, 28),
                    ),
                child: KeyboardFocusRevealer(
                  child: ListView(
                    key: PageStorageKey(title ?? 'page'),
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      16,
                      horizontal,
                      bottomPad,
                    ),
                    children: content,
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return KeyboardFocusRevealer(
        child: ListView(
          key: PageStorageKey(title ?? 'page'),
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            hasHeader ? 80 : 16,
            horizontal,
            bottomPad,
          ),
          children: hasHeader
              ? [header, const SizedBox(height: 16), ...content]
              : [...content],
        ),
      );
    },
  );
}

class SectionHeading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeading(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext c) => Row(
    children: [
      Expanded(child: Text(text, style: Theme.of(c).textTheme.titleLarge)),
      ?trailing,
    ],
  );
}

class EmptyState extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  const EmptyState(this.title, this.detail, this.icon, {super.key});
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        Icon(icon, size: 30, color: Theme.of(c).colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class NumberValue extends StatelessWidget {
  final String value;
  final double size;
  const NumberValue(this.value, {super.key, this.size = 38});
  @override
  Widget build(BuildContext c) => AnimatedSwitcher(
    duration: Motion.duration(c, 150),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: FittedBox(
      key: ValueKey(value),
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'Geist Mono',
          fontSize: size,
          letterSpacing: -1.4,
        ),
      ),
    ),
  );
}

class PillNavigation extends StatefulWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final ValueChanged<String> onQuickAdd;
  final PageController? tabController;
  final ValueListenable<bool>? swiping;
  const PillNavigation({
    super.key,
    required this.index,
    required this.onChanged,
    required this.onQuickAdd,
    this.tabController,
    this.swiping,
  });
  @override
  State<PillNavigation> createState() => _PillNavigationState();
}

class _PillNavigationState extends State<PillNavigation>
    with TickerProviderStateMixin {
  final keys = List.generate(4, (_) => GlobalKey());
  final _plusKey = GlobalKey();
  final optionKeys = List.generate(5, (_) => GlobalKey());
  final track = GlobalKey();
  late final AnimationController motion;
  AnimationController? _radialControllerInstance;

  AnimationController get _radialController => _radialControllerInstance ??=
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
        reverseDuration: const Duration(milliseconds: 340),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && _radialClosing) {
          _removeRadialEntry();
        }
      });
  Rect? from, target;
  List<Rect?> _tabRects = List<Rect?>.filled(4, null);
  OverlayEntry? _radialEntry;
  OverlayEntry? _tooltipEntry;
  int? hovered;
  final List<double> _press = List<double>.filled(4, 1.0);
  double _plusPress = 1.0;
  bool _longPressActive = false;
  bool _radialClosing = false;
  bool _dispatchingQuickAdd = false;
  int? _activePointer;
  Offset? _pointerDownPos;
  Offset? _lastPointerPos;
  Timer? _holdTimer;
  Offset? _lastPlusCenter;
  Timer? _tooltipTimer;
  int? _lastIndex;
  bool _forceUnderlineAnimation = false;

  static const labels = ['Home', 'Map', 'Sessions', 'Finance'];
  static const icons = [
    LucideIcons.house,
    LucideIcons.map,
    LucideIcons.table2,
    LucideIcons.philippinePeso,
  ];
  static const actions = ['session', 'expense', 'income', 'savings', 'rule'];
  static const actionLabels = [
    'Session / log',
    'Expense',
    'Income',
    'Savings',
    'Budget rule',
  ];
  static const actionIcons = [
    LucideIcons.clock3,
    LucideIcons.wallet,
    LucideIcons.plus,
    LucideIcons.piggyBank,
    LucideIcons.slidersHorizontal,
  ];

  bool get isRadialOpen => _radialEntry != null && !_radialClosing;

  @override
  void initState() {
    super.initState();
    motion = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _forceUnderlineAnimation &&
            mounted) {
          setState(() => _forceUnderlineAnimation = false);
        }
      });
    _radialController;
    WidgetsBinding.instance.addPostFrameCallback((_) => measure());
  }

  @override
  void didUpdateWidget(covariant PillNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      closeRadialMenu(immediate: true);
      _lastIndex = oldWidget.index;
      _forceUnderlineAnimation =
          widget.index >= 0 &&
          oldWidget.index >= 0 &&
          (widget.index - oldWidget.index).abs() > 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        measure();
        _showNavTooltip();
      });
    }
  }

  void _removeTooltip() {
    _tooltipTimer?.cancel();
    _tooltipTimer = null;
    _tooltipEntry?.remove();
    _tooltipEntry = null;
  }

  void _showNavTooltip([int? index]) {
    if (!mounted) return;
    final i = index ?? widget.index;
    if (i < 0 || i >= keys.length) return;
    final selectedKey = keys[i];
    final itemBox =
        selectedKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    if (itemBox == null || !itemBox.hasSize || overlay == null) return;
    _removeTooltip();
    final center = itemBox.localToGlobal(Offset(itemBox.size.width / 2, 0));
    final label = labels[i];
    _tooltipEntry = OverlayEntry(
      builder: (c) => Positioned(
        left: center.dx - 80,
        top: center.dy - 36,
        width: 160,
        child: IgnorePointer(
          child: Center(child: _NavTooltip(label: label)),
        ),
      ),
    );
    overlay.insert(_tooltipEntry!);
    _tooltipTimer = Timer(const Duration(milliseconds: 1800), _removeTooltip);
  }

  Rect? _rectAtPage(double page) {
    if (_tabRects.every((r) => r == null)) return target;
    final p = page.clamp(0.0, (keys.length - 1).toDouble());
    final i = p.floor().clamp(0, keys.length - 1);
    final j = p.ceil().clamp(0, keys.length - 1);
    final a = _tabRects[i] ?? _tabRects[j];
    final b = _tabRects[j] ?? _tabRects[i];
    if (a == null || b == null) return target;
    return Rect.lerp(a, b, p - i);
  }

  Rect? get current {
    final controller = widget.tabController;
    if (_forceUnderlineAnimation) {
      if (target == null || from == null) return target;
      final t = Curves.easeOutCubic.transform(motion.value.clamp(0.0, 1.0));
      return Rect.lerp(from, target, t);
    }
    if (controller != null && controller.hasClients) {
      final page = controller.page ?? widget.index.toDouble();
      return _rectAtPage(page);
    }
    if (target == null || from == null) return target;
    final t = Curves.easeOutCubic.transform(motion.value.clamp(0.0, 1.0));
    return Rect.lerp(from, target, t);
  }

  void measure() {
    final parent = track.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || parent == null) return;
    final rects = List<Rect?>.filled(keys.length, null);
    for (var i = 0; i < keys.length; i++) {
      final box = keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        rects[i] = box.localToGlobal(Offset.zero, ancestor: parent) & box.size;
      }
    }
    final next = (widget.index >= 0 && widget.index < rects.length)
        ? rects[widget.index]
        : null;
    final controllerDriven =
        widget.tabController != null && widget.tabController!.hasClients;
    final changed =
        !_sameRects(_tabRects, rects) ||
        target != next ||
        _forceUnderlineAnimation;
    if (!changed) return;
    setState(() {
      _tabRects = rects;
      if (_forceUnderlineAnimation) {
        final prev =
            (_lastIndex != null &&
                _lastIndex! >= 0 &&
                _lastIndex! < rects.length)
            ? rects[_lastIndex!]
            : (from ?? target ?? next);
        from = prev ?? next;
        target = next;
        motion.duration = Motion.duration(context, 320);
        motion.forward(from: 0);
      } else if (controllerDriven) {
        target = next;
        from = next;
      } else {
        from = current ?? next;
        target = next;
        motion.duration = Motion.duration(context, 320);
        motion.forward(from: 0);
      }
    });
  }

  bool _sameRects(List<Rect?> a, List<Rect?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _setPressed(int i, bool down) {
    if (!mounted) return;
    setState(() => _press[i] = down ? 0.9 : 1.0);
  }

  void _setPlusPressed(bool down) {
    if (!mounted || _plusPress == (down ? 0.9 : 1.0)) return;
    setState(() => _plusPress = down ? 0.9 : 1.0);
  }

  void _triggerQuickAdd(String kind) {
    if (_dispatchingQuickAdd) return;
    _dispatchingQuickAdd = true;
    scheduleMicrotask(() => _dispatchingQuickAdd = false);
    widget.onQuickAdd(kind);
  }

  Offset _resolvePlusCenter(BuildContext overlayContext) {
    final plusBox = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = overlayContext.findRenderObject() as RenderBox?;
    if (plusBox != null && plusBox.hasSize) {
      final center = plusBox.localToGlobal(
        Offset(plusBox.size.width / 2, plusBox.size.height / 2),
        ancestor: overlayBox,
      );
      _lastPlusCenter = center;
      return center;
    }
    final trackBox = track.currentContext?.findRenderObject() as RenderBox?;
    if (trackBox != null && trackBox.hasSize) {
      final center = trackBox.localToGlobal(
        Offset(trackBox.size.width / 2, trackBox.size.height / 2),
        ancestor: overlayBox,
      );
      _lastPlusCenter = center;
      return center;
    }
    return _lastPlusCenter ?? Offset.zero;
  }

  Offset _radialOffset(
    int index,
    int count,
    Size screen,
    EdgeInsets padding,
    Offset origin,
  ) {
    final arcSpan = count <= 1
        ? 0.0
        : math.min(math.pi * 0.84, (count - 1) * (math.pi / 4.6));
    final startAngle = -math.pi / 2 - arcSpan / 2;
    final angle = count <= 1
        ? -math.pi / 2
        : startAngle + index * (arcSpan / (count - 1));
    final maxHorizontal = math.min(
      origin.dx - padding.left - 34.0,
      screen.width - padding.right - origin.dx - 34.0,
    );
    final radius = math.min(118.0, maxHorizontal / 0.94).clamp(90.0, 126.0);
    final minX = padding.left + 32.0;
    final maxX = math.max(minX, screen.width - padding.right - 32.0);
    final minY = padding.top + 32.0;
    final maxY = math.max(minY, screen.height - padding.bottom - 32.0);
    final targetX = (origin.dx + radius * math.cos(angle)).clamp(minX, maxX);
    final targetY = (origin.dy + radius * math.sin(angle)).clamp(minY, maxY);
    return Offset(targetX - origin.dx, targetY - origin.dy);
  }

  ({double linear, double spring}) _radialItemProgress(
    int index,
    int count,
    bool disableAnimations,
  ) {
    final t = _radialController.value.clamp(0.0, 1.0);
    if (disableAnimations || count <= 1) {
      return (linear: t, spring: t);
    }
    final stagger = math.min(0.055, 0.24 / (count - 1));
    final span = 1.0 - stagger * (count - 1);
    final start = index * stagger;
    final u = ((t - start) / span).clamp(0.0, 1.0);
    final reversing =
        _radialClosing || _radialController.status == AnimationStatus.reverse;
    final spring = reversing
        ? 1.0 - Curves.easeInCubic.transform(1.0 - u)
        : Motion.settle.transform(u);
    return (linear: u, spring: spring);
  }

  double _plusRotationAngle(bool disableAnimations) {
    final t = _radialController.value.clamp(0.0, 1.0);
    if (disableAnimations) return t * (math.pi / 4);
    final reversing =
        _radialClosing || _radialController.status == AnimationStatus.reverse;
    final curved = reversing
        ? 1.0 - Motion.settle.transform(1.0 - t)
        : Motion.settle.transform(t);
    return curved * (math.pi / 4);
  }

  void _removeRadialEntry() {
    _radialClosing = false;
    hovered = null;
    _radialEntry?.remove();
    _radialEntry = null;
    if (mounted) setState(() {});
  }

  void toggleRadialMenu() {
    if (_longPressActive) return;
    if (isRadialOpen) {
      closeRadialMenu(feedback: true);
    } else {
      openRadialMenu();
    }
  }

  void openRadialMenu({bool fast = false}) {
    if (!mounted) return;
    ActionFeedback.tap();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    _radialClosing = false;
    _radialController.duration = Motion.duration(context, fast ? 150 : 360);
    _radialController.reverseDuration = Motion.duration(context, 280);
    if (_radialEntry == null) {
      _radialEntry = OverlayEntry(
        builder: (overlayContext) =>
            themes.wrap(_buildRadialOverlay(overlayContext)),
      );
      overlay.insert(_radialEntry!);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _radialController.value = 1.0;
    } else {
      final startValue = fast
          ? math.max(_radialController.value, 0.35)
          : _radialController.value;
      _radialController.forward(from: startValue);
    }
    setState(() {});
  }

  void closeRadialMenu({bool immediate = false, bool feedback = false}) {
    if (_radialEntry == null) return;
    if (feedback) ActionFeedback.tap();
    hovered = null;
    if (immediate || !mounted || MediaQuery.disableAnimationsOf(context)) {
      _radialController.stop();
      _radialController.value = 0.0;
      _removeRadialEntry();
      return;
    }
    if (_radialClosing) return;
    _radialClosing = true;
    _radialController.reverseDuration = Motion.duration(context, 280);
    _radialController.reverse();
    if (mounted) setState(() {});
  }

  void _updateRadialHover(Offset globalPosition) {
    if (!mounted) return;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safePadding = media.viewPadding;
    final overlay = Overlay.maybeOf(context);
    final origin = _resolvePlusCenter(overlay?.context ?? context);
    final delta = globalPosition - origin;
    final distFromOrigin = delta.distance;

    int? next;
    var bestOrbDistance = 40.0;
    for (var i = 0; i < actions.length; i++) {
      final targetCenter =
          origin +
          _radialOffset(i, actions.length, screen, safePadding, origin);
      final distance = (globalPosition - targetCenter).distance;
      if (distance <= bestOrbDistance) {
        bestOrbDistance = distance;
        next = i;
      }
    }

    if (next == null &&
        distFromOrigin >= 18.0 &&
        distFromOrigin <= 145.0 &&
        delta.dy <= 18.0) {
      final swipeAngle = math.atan2(delta.dy, delta.dx);
      var bestAngleDiff = 0.48;
      for (var i = 0; i < actions.length; i++) {
        final offset = _radialOffset(
          i,
          actions.length,
          screen,
          safePadding,
          origin,
        );
        final itemAngle = math.atan2(offset.dy, offset.dx);
        var diff = (swipeAngle - itemAngle).abs();
        if (diff > math.pi) diff = 2 * math.pi - diff;
        if (diff <= bestAngleDiff) {
          bestAngleDiff = diff;
          next = i;
        }
      }
    }

    if (next == hovered) return;
    hovered = next;
    if (next != null) ActionFeedback.tap();
    _radialEntry?.markNeedsBuild();
  }

  Widget _buildPlusOrb(BuildContext c, {required bool active}) {
    final scheme = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final disableAnimations = MediaQuery.disableAnimationsOf(c);
    return AnimatedBuilder(
      animation: _radialController,
      builder: (context, _) {
        final progress = _radialController.value.clamp(0.0, 1.0);
        final angle = _plusRotationAngle(disableAnimations);
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(
                  alpha: dark ? (.16 + .10 * progress) : (.72 + .16 * progress),
                ),
                scheme.onSurface.withValues(
                  alpha: dark ? (.08 + .08 * progress) : (.05 + .06 * progress),
                ),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: dark ? (.22 + .12 * progress) : (.78 + .14 * progress),
              ),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .26 : .10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Transform.rotate(
              angle: angle,
              child: Icon(
                LucideIcons.plus,
                size: 17,
                color: active
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: .92),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRadialOverlay(BuildContext overlayContext) {
    final media = MediaQuery.of(overlayContext);
    final screen = media.size;
    final safePadding = media.viewPadding;
    final disableAnimations = media.disableAnimations;
    final scheme = Theme.of(overlayContext).colorScheme;
    final dark = Theme.of(overlayContext).brightness == Brightness.dark;
    final origin = _resolvePlusCenter(overlayContext);
    const orbSize = 48.0;
    final targets = List<Offset>.generate(
      actions.length,
      (i) => _radialOffset(i, actions.length, screen, safePadding, origin),
      growable: false,
    );
    final orbBodies = List<Widget>.generate(
      actions.length,
      (i) => RepaintBoundary(
        child: _RadialActionOrb(
          key: optionKeys[i],
          size: orbSize,
          icon: actionIcons[i],
          hovered: hovered == i,
          scheme: scheme,
          dark: dark,
        ),
      ),
      growable: false,
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: const ValueKey('radial-action-menu'),
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _radialController,
              builder: (c, _) {
                final t = _radialController.value.clamp(0.0, 1.0);
                final scrimAlpha =
                    (dark ? 0.34 : 0.16) * Curves.easeOut.transform(t);
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => closeRadialMenu(feedback: true),
                  onPanStart: (d) => _updateRadialHover(d.globalPosition),
                  onPanUpdate: (d) => _updateRadialHover(d.globalPosition),
                  onPanEnd: (d) {
                    _updateRadialHover(d.globalPosition);
                    final selection = hovered;
                    closeRadialMenu();
                    if (selection != null) _triggerQuickAdd(actions[selection]);
                  },
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: scrimAlpha),
                  ),
                );
              },
            ),
          ),
          for (var i = 0; i < actions.length; i++)
            Positioned(
              left: origin.dx + targets[i].dx - orbSize / 2,
              top: origin.dy + targets[i].dy - orbSize / 2,
              width: orbSize,
              height: orbSize,
              child: AnimatedBuilder(
                animation: _radialController,
                child: Semantics(
                  button: true,
                  selected: hovered == i,
                  label: actionLabels[i],
                  child: GestureDetector(
                    key: ValueKey('radial-action-${actions[i]}'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      if (_radialClosing) return;
                      if (hovered != i) {
                        hovered = i;
                        ActionFeedback.tap();
                        _radialEntry?.markNeedsBuild();
                      }
                    },
                    onTapCancel: () {
                      if (hovered == i) {
                        hovered = null;
                        _radialEntry?.markNeedsBuild();
                      }
                    },
                    onTap: () {
                      if (_radialClosing) return;
                      final selectedAction = actions[i];
                      closeRadialMenu();
                      _triggerQuickAdd(selectedAction);
                    },
                    child: orbBodies[i],
                  ),
                ),
                builder: (c, child) {
                  final progress = _radialItemProgress(
                    i,
                    actions.length,
                    disableAnimations,
                  );
                  final dx = targets[i].dx * (progress.spring - 1.0);
                  final dy = targets[i].dy * (progress.spring - 1.0);
                  final scale = progress.spring.clamp(0.0, 1.15);
                  final opacity = Curves.easeOut
                      .transform(progress.linear)
                      .clamp(0.0, 1.0);
                  return IgnorePointer(
                    ignoring: _radialClosing || progress.linear < 0.08,
                    child: Transform.translate(
                      offset: Offset(dx, dy),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: Opacity(opacity: opacity, child: child),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (hovered != null)
            Positioned(
              left: (origin.dx - 96).clamp(
                safePadding.left + 12.0,
                math.max(
                  safePadding.left + 12.0,
                  screen.width - safePadding.right - 204.0,
                ),
              ),
              top: math.max(safePadding.top + 12.0, origin.dy - 62.0),
              width: 192,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const ValueKey('radial-active-label'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: dark ? .94 : .97),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(
                          alpha: dark ? .45 : .65,
                        ),
                        width: 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? .40 : .14,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      actionLabels[hovered!],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: origin.dx - 19,
            top: origin.dy - 19,
            width: 38,
            height: 38,
            child: Listener(
              key: const ValueKey('radial-close-button'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPlusPointerDown,
              onPointerMove: _onPlusPointerMove,
              onPointerUp: _onPlusPointerUp,
              onPointerCancel: _onPlusPointerCancel,
              child: Center(child: _buildPlusOrb(overlayContext, active: true)),
            ),
          ),
        ],
      ),
    );
  }

  void _startHoldDrag(Offset globalPosition, {bool fast = false}) {
    if (!mounted) return;
    _setPlusPressed(false);
    _longPressActive = true;
    hovered = null;
    if (!isRadialOpen) {
      openRadialMenu(fast: fast);
    }
    _updateRadialHover(globalPosition);
  }

  void _onPlusPointerDown(PointerDownEvent e) {
    _holdTimer?.cancel();
    _activePointer = e.pointer;
    _pointerDownPos = e.position;
    _lastPointerPos = e.position;
    _longPressActive = false;
    _setPlusPressed(true);
    _holdTimer = Timer(const Duration(milliseconds: 140), () {
      if (_activePointer == e.pointer && !_longPressActive) {
        _startHoldDrag(_lastPointerPos ?? e.position, fast: true);
      }
    });
  }

  void _onPlusPointerMove(PointerMoveEvent e) {
    if (_activePointer != e.pointer) return;
    _lastPointerPos = e.position;
    if (!_longPressActive) {
      final down = _pointerDownPos ?? e.position;
      if ((e.position - down).distance > 4.0) {
        _holdTimer?.cancel();
        _startHoldDrag(e.position, fast: true);
      }
      return;
    }
    if (_radialEntry != null) {
      _updateRadialHover(e.position);
    }
  }

  void _onPlusPointerUp(PointerUpEvent e) {
    if (_activePointer != e.pointer) return;
    _holdTimer?.cancel();
    _activePointer = null;
    _pointerDownPos = null;
    _lastPointerPos = null;
    _setPlusPressed(false);
    if (_longPressActive) {
      if (_radialEntry == null) {
        _longPressActive = false;
        return;
      }
      _updateRadialHover(e.position);
      final selection = hovered;
      _longPressActive = false;
      closeRadialMenu();
      if (selection != null) _triggerQuickAdd(actions[selection]);
      return;
    }
    toggleRadialMenu();
  }

  void _onPlusPointerCancel(PointerCancelEvent e) {
    if (_activePointer != null && _activePointer != e.pointer) return;
    _holdTimer?.cancel();
    _activePointer = null;
    _pointerDownPos = null;
    _lastPointerPos = null;
    _setPlusPressed(false);
    if (_longPressActive) {
      _longPressActive = false;
      closeRadialMenu();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    closeRadialMenu(immediate: true);
    _removeTooltip();
    _radialControllerInstance?.dispose();
    motion.dispose();
    super.dispose();
  }

  Widget _buildTabItem(BuildContext c, int i) {
    final scheme = Theme.of(c).colorScheme;
    final selected = widget.index == i;
    final color = selected
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: .82);
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: labels[i],
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(i, true),
          onTapCancel: () => _setPressed(i, false),
          onTapUp: (_) => _setPressed(i, false),
          onTap: () {
            closeRadialMenu();
            _showNavTooltip(i);
            widget.onChanged(i);
          },
          child: SizedBox(
            key: keys[i],
            height: 38,
            child: AnimatedScale(
              scale: _press[i],
              duration: Motion.duration(c, 120),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                duration: Motion.duration(c, 160),
                opacity: selected ? 1.0 : 0.72,
                child: Center(child: Icon(icons[i], size: 20, color: color)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    return Semantics(
      label:
          'Navigation. Tap center to expand actions, or hold and drag to add.',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Add session or log'): () =>
            _triggerQuickAdd('session'),
        const CustomSemanticsAction(label: 'Add expense'): () =>
            _triggerQuickAdd('expense'),
        const CustomSemanticsAction(label: 'Add income'): () =>
            _triggerQuickAdd('income'),
        const CustomSemanticsAction(label: 'Add savings'): () =>
            _triggerQuickAdd('savings'),
        const CustomSemanticsAction(label: 'Add budget rule'): () =>
            _triggerQuickAdd('rule'),
      },
      child: Listener(
        onPointerCancel: _onPlusPointerCancel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .34 : .14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .20 : .08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: ValueListenableBuilder<bool>(
              valueListenable:
                  widget.swiping ?? const AlwaysStoppedAnimation(false),
              builder: (context, swiping, child) => GlassContainer(
                useOwnLayer: true,
                shape: const LiquidRoundedSuperellipse(borderRadius: 28),
                settings: LiquidGlassSettings(
                  blur: swiping ? 0 : 18,
                  thickness: swiping ? 8 : 18,
                ),
                padding: EdgeInsets.zero,
                child: child!,
              ),
              child: Container(
                height: 46,
                width: 252,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: scheme.surface.withValues(alpha: dark ? .52 : .62),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dark ? .12 : .55),
                    width: 0.8,
                  ),
                ),
                child: Stack(
                  key: track,
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        motion,
                        if (widget.tabController != null) widget.tabController!,
                      ]),
                      builder: (c, _) {
                        final rect = current;
                        if (rect == null) return const SizedBox.shrink();
                        const underlineWidth = 14.0;
                        const underlineHeight = 3.0;
                        return Positioned(
                          left: rect.left,
                          width: rect.width,
                          top: rect.bottom - 5,
                          height: underlineHeight,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                width: underlineWidth,
                                height: underlineHeight,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34C759),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      children: [
                        _buildTabItem(c, 0),
                        _buildTabItem(c, 1),
                        Semantics(
                          button: true,
                          toggled: isRadialOpen,
                          label: isRadialOpen
                              ? 'Close quick actions'
                              : 'Quick actions',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (_) {},
                            onHorizontalDragUpdate: (_) {},
                            onVerticalDragStart: (_) {},
                            onVerticalDragUpdate: (_) {},
                            child: Listener(
                              key: const ValueKey('nav-plus-button'),
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: _onPlusPointerDown,
                              onPointerMove: _onPlusPointerMove,
                              onPointerUp: _onPlusPointerUp,
                              onPointerCancel: _onPlusPointerCancel,
                              child: SizedBox(
                                key: _plusKey,
                                width: 38,
                                height: 38,
                                child: AnimatedScale(
                                  scale: _plusPress,
                                  duration: Motion.duration(c, 120),
                                  curve: Curves.easeOutCubic,
                                  child: Center(
                                    child: _buildPlusOrb(
                                      c,
                                      active: isRadialOpen,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildTabItem(c, 2),
                        _buildTabItem(c, 3),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadialActionOrb extends StatelessWidget {
  final double size;
  final IconData icon;
  final bool hovered;
  final ColorScheme scheme;
  final bool dark;

  const _RadialActionOrb({
    super.key,
    required this.size,
    required this.icon,
    required this.hovered,
    required this.scheme,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: hovered ? 1.12 : 1.0,
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hovered
              ? scheme.primaryContainer
              : scheme.surface.withValues(alpha: dark ? .92 : .96),
          border: Border.all(
            color: hovered
                ? scheme.primary.withValues(alpha: .85)
                : scheme.outlineVariant.withValues(alpha: dark ? .45 : .65),
            width: hovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .36 : .14),
              blurRadius: hovered ? 14 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: 22,
              color: hovered ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

final _toastDismissals = Expando<VoidCallback>();

void toast(
  BuildContext c,
  String message, {
  bool error = false,
  IconData? icon,
}) {
  final overlay = Overlay.of(c, rootOverlay: true);
  _toastDismissals[overlay]?.call();
  late OverlayEntry entry;
  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    _toastDismissals[overlay] = null;
    entry.remove();
    entry.dispose();
  }

  final themes = InheritedTheme.capture(from: c, to: overlay.context);
  entry = OverlayEntry(
    builder: (c) => Positioned(
      top: MediaQuery.paddingOf(c).top + 16,
      left: MediaQuery.paddingOf(c).left + 16,
      right: MediaQuery.paddingOf(c).right + 16,
      child: themes.wrap(
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: math.max(80, MediaQuery.sizeOf(c).height * .4),
            ),
            child: _Toast(
              message: message,
              error: error,
              icon: icon,
              done: dismiss,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _toastDismissals[overlay] = dismiss;
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final IconData? icon;
  final VoidCallback done;
  const _Toast({
    required this.message,
    required this.error,
    this.icon,
    required this.done,
  });
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    reverseDuration: const Duration(milliseconds: 350),
  );
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer(Duration(seconds: widget.error ? 8 : 4), () async {
      if (!mounted) {
        return;
      }
      try {
        await controller.reverse().orCancel;
        if (mounted) {
          widget.done();
        }
      } on TickerCanceled {
        /* Overlay was already dismissed. */
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.duration = Motion.duration(context, 400);
    controller.reverseDuration = Motion.duration(context, 350);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => FadeTransition(
    opacity: controller,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, -.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: controller, curve: Motion.curve)),
      child: Material(
        color: Colors.transparent,
        child: Surface(
          key: const ValueKey('top-toast-pill'),
          floating: true,
          borderRadius: BorderRadius.circular(40),
          padding: const EdgeInsets.all(10),
          child: Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.error
                      ? LucideIcons.circleAlert
                      : widget.icon ?? LucideIcons.circleCheck,
                  size: 20,
                  color: widget.error
                      ? Theme.of(c).colorScheme.error
                      : Theme.of(c).colorScheme.onSurface,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: SingleChildScrollView(child: Text(widget.message)),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Dismiss message',
                  onPressed: withFeedback(widget.done),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 20),
                    maximumSize: const Size(20, 20),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                  ),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class BounceFilterChip extends StatefulWidget {
  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  const BounceFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  @override
  State<BounceFilterChip> createState() => _BounceFilterChipState();
}

class _BounceFilterChipState extends State<BounceFilterChip> {
  double scale = 1;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedScale(
    scale: MediaQuery.disableAnimationsOf(c) ? 1 : scale,
    duration: Motion.duration(c, 250),
    curve: Motion.settle,
    child: FilterChip(
      label: widget.label,
      selected: widget.selected,
      onSelected: (v) {
        ActionFeedback.tap();
        widget.onSelected(v);
        if (!MediaQuery.disableAnimationsOf(c)) {
          setState(() => scale = 1.08);
          timer?.cancel();
          timer = Timer(const Duration(milliseconds: 150), () {
            if (mounted) {
              setState(() => scale = 1);
            }
          });
        }
      },
    ),
  );
}

class _NavTooltip extends StatefulWidget {
  final String label;
  const _NavTooltip({required this.label});

  @override
  State<_NavTooltip> createState() => _NavTooltipState();
}

class _NavTooltipState extends State<_NavTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();
  late final Timer _hide = Timer(const Duration(milliseconds: 1400), () {
    if (mounted) _c.reverse();
  });

  @override
  void dispose() {
    _hide.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fade = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: dark ? .94 : .97),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: .08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .14),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
