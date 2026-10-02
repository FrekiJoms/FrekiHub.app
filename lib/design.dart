import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'services.dart';
part 'flip_clock.dart';

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
        shape: const StadiumBorder(),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
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

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .018),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Chrome extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Chrome({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
  });
  @override
  Widget build(BuildContext context) => GlassContainer(
    useOwnLayer: true,
    shape: const LiquidRoundedSuperellipse(borderRadius: 40),
    settings: const LiquidGlassSettings(blur: 12, thickness: 24),
    padding: padding,
    child: child,
  );
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

class PageBody extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final Widget? action;
  const PageBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });
  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, constraints) {
      final inset = constraints.maxWidth < 380 ? 16.0 : 24.0;
      final horizontal = math.max(inset, (constraints.maxWidth - 720) / 2);
      return ListView(
        key: PageStorageKey(title),
        padding: EdgeInsets.fromLTRB(
          horizontal,
          16,
          horizontal,
          126 + MediaQuery.paddingOf(c).bottom,
        ),
        children: [
          Entrance(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 56),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
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
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(c).textTheme.headlineLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Entrance(index: i + 1, child: children[i]),
            ),
        ],
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
  static const labels = ['Today', 'Calendar', 'Sessions', 'Budget'];
  static const icons = [
    LucideIcons.clock3,
    LucideIcons.calendarDays,
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
          elevation: 12,
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

Future<bool> confirm(
  BuildContext c,
  String title,
  String detail, {
  String action = 'Delete',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: withFeedback(() => Navigator.pop(c, false)),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: withFeedback(() => Navigator.pop(c, true)),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<T?> panel<T>(BuildContext c, Widget child) => showModalBottomSheet<T>(
  context: c,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxWidth: 640,
    maxHeight: MediaQuery.sizeOf(c).height * .92,
  ),
  sheetAnimationStyle: AnimationStyle(
    duration: Motion.duration(c, 400),
    reverseDuration: Motion.duration(c, 350),
  ),
  builder: (c) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
    child: child,
  ),
);
void toast(BuildContext c, String message) {
  final overlay = Overlay.of(c);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (c) => Positioned(
      top: MediaQuery.paddingOf(c).top + 16,
      left: 24,
      right: 24,
      child: _Toast(message: message, done: entry.remove),
    ),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final VoidCallback done;
  const _Toast({required this.message, required this.done});
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
    timer = Timer(const Duration(seconds: 3), () async {
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
  Widget build(BuildContext c) => IgnorePointer(
    child: FadeTransition(
      opacity: controller,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: controller, curve: Motion.curve)),
        child: Material(
          color: Colors.transparent,
          child: Chrome(
            padding: const EdgeInsets.all(18),
            child: Semantics(
              liveRegion: true,
              child: Text(widget.message, textAlign: TextAlign.center),
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
