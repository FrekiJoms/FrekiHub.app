import 'dart:math' as math;
import 'dart:async';

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
                              color: Theme.of(c).colorScheme.onSurfaceVariant,
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
      final content = <Widget>[
        if (leading != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: leading),
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Entrance(index: i + 1, child: children[i]),
          ),
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
                child: ListView(
                   key: PageStorageKey(title ?? 'page'),
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    16,
                    horizontal,
                    126 + MediaQuery.paddingOf(c).bottom,
                  ),
                  children: content,
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        key: PageStorageKey(title ?? 'page'),
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          horizontal,
          hasHeader ? 80 : 16,
          horizontal,
          126 + MediaQuery.paddingOf(c).bottom,
        ),
        children: hasHeader
            ? [header, const SizedBox(height: 16), ...content]
            : [...content],
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
  const PillNavigation({
    super.key,
    required this.index,
    required this.onChanged,
    required this.onQuickAdd,
  });
  @override
  State<PillNavigation> createState() => _PillNavigationState();
}

class _PillNavigationState extends State<PillNavigation>
    with SingleTickerProviderStateMixin {
  final keys = List.generate(4, (_) => GlobalKey());
  final optionKeys = List.generate(5, (_) => GlobalKey());
  final track = GlobalKey();
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  Rect? from, target;
  OverlayEntry? menu;
  int? hovered;
  static const labels = ['Home', 'Map', 'Sessions', 'Finance'];
  static const icons = [
    LucideIcons.house,
    LucideIcons.map,
    LucideIcons.table2,
    LucideIcons.wallet,
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

  Rect? get current {
    if (target == null || from == null) return target;
    final leading = Motion.curve.transform((motion.value / .7).clamp(0.0, 1.0));
    final trailing = Motion.curve.transform(
      ((motion.value - .22) / .78).clamp(0.0, 1.0),
    );
    final rightward = target!.center.dx >= from!.center.dx;
    double mix(double a, double b, double t) => a + (b - a) * t;
    return Rect.fromLTRB(
      mix(from!.left, target!.left, rightward ? trailing : leading),
      mix(from!.top, target!.top, leading),
      mix(from!.right, target!.right, rightward ? leading : trailing),
      mix(from!.bottom, target!.bottom, leading),
    );
  }

  void measure() {
    final parent = track.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || parent == null) return;
    final selected = widget.index < keys.length
        ? keys[widget.index].currentContext?.findRenderObject() as RenderBox?
        : null;
    final next = selected == null
        ? null
        : selected.localToGlobal(Offset.zero, ancestor: parent) & selected.size;
    if (target == next) return;
    setState(() {
      from = current ?? next;
      target = next;
      motion.duration = Motion.duration(context);
      motion.forward(from: 0);
    });
  }

  void closeMenu() {
    menu?.remove();
    menu = null;
    hovered = null;
  }

  void openMenu() {
    closeMenu();
    ActionFeedback.tap();
    final box = track.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(280.0, screen.width - 32);
    menu = OverlayEntry(
      builder: (c) => Positioned(
        left: (origin.dx + box.size.width / 2 - width / 2).clamp(
          16.0,
          screen.width - width - 16,
        ),
        bottom: screen.height - origin.dy + 12,
        width: width,
        child: Material(
          color: Theme.of(c).colorScheme.surfaceContainerHigh,
          elevation: FloatingDepth.elevation,
          shadowColor: FloatingDepth.color(c),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Drag to add · release to select',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                for (var i = 0; i < actions.length; i++)
                  AnimatedContainer(
                    key: optionKeys[i],
                    duration: Motion.duration(c, 150),
                    decoration: BoxDecoration(
                      color: hovered == i
                          ? Theme.of(c).colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(actionIcons[i], size: 20),
                          const SizedBox(width: 14),
                          Text(actionLabels[i]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(menu!);
  }

  void updateMenu(Offset position) {
    int? next;
    for (var i = 0; i < optionKeys.length; i++) {
      final box =
          optionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
        next = i;
      }
    }
    if (next == hovered) return;
    hovered = next;
    if (next != null) ActionFeedback.tap();
    menu?.markNeedsBuild();
  }

  @override
  void dispose() {
    closeMenu();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    WidgetsBinding.instance.addPostFrameCallback((_) => measure());
    return Semantics(
      label: 'Navigation. Hold the center and drag to add.',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Add session or log'): () =>
            widget.onQuickAdd('session'),
        const CustomSemanticsAction(label: 'Add expense'): () =>
            widget.onQuickAdd('expense'),
        const CustomSemanticsAction(label: 'Add income'): () =>
            widget.onQuickAdd('income'),
        const CustomSemanticsAction(label: 'Add savings'): () =>
            widget.onQuickAdd('savings'),
        const CustomSemanticsAction(label: 'Add budget rule'): () =>
            widget.onQuickAdd('rule'),
      },
      child: GestureDetector(
        onLongPressStart: (d) {
          final box = track.currentContext!.findRenderObject() as RenderBox;
          final local = box.globalToLocal(d.globalPosition);
          if ((local.dx - box.size.width / 2).abs() <= 36) openMenu();
        },
        onLongPressMoveUpdate: (d) {
          if (menu != null) updateMenu(d.globalPosition);
        },
        onLongPressCancel: closeMenu,
        onLongPressEnd: (d) {
          if (menu == null) return;
          updateMenu(d.globalPosition);
          final selection = hovered;
          closeMenu();
          if (selection != null) widget.onQuickAdd(actions[selection]);
        },
        child: Chrome(
          child: Stack(
            key: track,
            children: [
              AnimatedBuilder(
                animation: motion,
                builder: (c, _) {
                  final rect = current;
                  return rect == null
                      ? const SizedBox.shrink()
                      : Positioned.fromRect(
                          rect: rect,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(c).colorScheme.onSurface
                                    .withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(32),
                              ),
                            ),
                          ),
                        );
                },
              ),
              Row(
                children: List.generate(
                  labels.length,
                  (i) => Expanded(
                    child: Semantics(
                      selected: widget.index == i,
                      button: true,
                      label: labels[i],
                      child: InkWell(
                        key: keys[i],
                        borderRadius: BorderRadius.circular(32),
                        onTap: () => widget.onChanged(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icons[i],
                                size: 20,
                                color: widget.index == i
                                    ? Theme.of(c).colorScheme.onSurface
                                    : Theme.of(c).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                labels[i],
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: widget.index == i
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: widget.index == i
                                      ? Theme.of(c).colorScheme.onSurface
                                      : Theme.of(c)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
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
