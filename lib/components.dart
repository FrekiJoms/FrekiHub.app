part of 'design.dart';

/// Shared typography for primary page titles.
class PageTitle extends StatelessWidget {
  final String title;
  const PageTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title.replaceFirst(RegExp(r'\.+$'), '').toUpperCase(),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _KeyboardInsetScope extends InheritedWidget {
  final double bottom;
  const _KeyboardInsetScope({required this.bottom, required super.child});
  @override
  bool updateShouldNotify(_KeyboardInsetScope oldWidget) =>
      bottom != oldWidget.bottom;
}

/// Keeps outer navigation/layout bounds fixed while exposing raw IME height
/// selectively for sheet lift and focused-input scroll clearance.
class KeyboardOverlay extends StatelessWidget {
  final Widget child;
  const KeyboardOverlay({super.key, required this.child});

  /// Actual bottom IME inset in logical pixels behind [KeyboardOverlay].
  static double imeBottomOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_KeyboardInsetScope>();
    if (scope != null) return scope.bottom;
    return MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return _KeyboardInsetScope(
      bottom: media.viewInsets.bottom,
      child: MediaQuery(
        data: media.copyWith(
          viewInsets: EdgeInsets.zero,
          padding: media.viewPadding,
        ),
        child: child,
      ),
    );
  }
}

bool isContextDescendant(BuildContext? child, BuildContext? ancestor) {
  if (child == null ||
      ancestor == null ||
      !child.mounted ||
      !ancestor.mounted) {
    return false;
  }
  if (identical(child, ancestor)) return true;
  var found = false;
  child.visitAncestorElements((element) {
    if (identical(element, ancestor)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Locates the active editable control and target visibility bounds inside it.
({EditableTextState editable, RenderBox box, Rect localRect})?
focusedEditableTarget(FocusNode? focus) {
  final ctx = focus?.context;
  if (ctx == null || !ctx.mounted) return null;
  EditableTextState? editable;
  if (ctx.widget is EditableText) {
    editable = (ctx as StatefulElement).state as EditableTextState;
  } else {
    editable = ctx.findAncestorStateOfType<EditableTextState>();
  }
  if (editable == null || !editable.mounted) return null;

  RenderBox? box;
  editable.context.visitAncestorElements((element) {
    if (element.widget is InputDecorator) {
      final ro = element.findRenderObject();
      if (ro is RenderBox && ro.hasSize) box = ro;
      return false;
    }
    if (element.widget is TextField) return false;
    return true;
  });
  box ??= editable.context.findRenderObject() as RenderBox?;
  if (box == null || !box!.hasSize) return null;

  final boxSize = box!.size;
  var localRect = Offset.zero & boxSize;
  if (boxSize.height > 120) {
    final renderEditable = editable.renderEditable;
    final selection = editable.textEditingValue.selection;
    if (renderEditable.hasSize && selection.isValid) {
      final caret = renderEditable.getLocalRectForCaret(selection.extent);
      final topLeft = renderEditable.localToGlobal(
        caret.topLeft,
        ancestor: box,
      );
      final top = math.max(0.0, topLeft.dy - 12.0);
      final bottom = math.min(boxSize.height, topLeft.dy + caret.height + 20.0);
      localRect = Rect.fromLTRB(
        topLeft.dx,
        top,
        topLeft.dx + math.max(1.0, caret.width),
        math.max(top + 1.0, bottom),
      );
    }
  }
  return (editable: editable, box: box!, localRect: localRect);
}

/// Adds extra bottom scroll room while the IME overlays a scrollable page.
class KeyboardScrollSpacer extends StatelessWidget {
  final double baseBottom;
  const KeyboardScrollSpacer({super.key, this.baseBottom = 0});

  @override
  Widget build(BuildContext context) {
    final height = math.max(
      0.0,
      KeyboardOverlay.imeBottomOf(context) - baseBottom,
    );
    return SizedBox(height: height);
  }
}

/// Keeps the focused text input or caret scrolled clear of the active keyboard.
class KeyboardFocusRevealer extends StatefulWidget {
  final Widget child;
  const KeyboardFocusRevealer({super.key, required this.child});

  @override
  State<KeyboardFocusRevealer> createState() => _KeyboardFocusRevealerState();
}

class _KeyboardFocusRevealerState extends State<KeyboardFocusRevealer> {
  double _imeBottom = 0;
  bool _revealScheduled = false;
  TextEditingController? _controller;
  ScrollPosition? _animatingPosition;
  double? _animatingTarget;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
    _attachToCurrentFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextIme = KeyboardOverlay.imeBottomOf(context);
    final changed = (nextIme - _imeBottom).abs() > 0.5;
    _imeBottom = nextIme;
    if (changed && _imeBottom > 0) _scheduleReveal();
  }

  void _onFocusChange() {
    _attachToCurrentFocus();
    if (_imeBottom > 0) _scheduleReveal();
  }

  void _attachToCurrentFocus() {
    final target = focusedEditableTarget(FocusManager.instance.primaryFocus);
    final next =
        (target != null &&
            isContextDescendant(target.editable.context, context))
        ? target.editable.widget.controller
        : null;
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onTextChange);
      _controller = next;
      _controller?.addListener(_onTextChange);
    }
  }

  void _onTextChange() {
    if (_imeBottom > 0) _scheduleReveal();
  }

  void _scheduleReveal() {
    if (_revealScheduled || !mounted) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      _reveal();
    });
  }

  void _reveal() {
    if (!mounted || _imeBottom <= 0) return;
    final target = focusedEditableTarget(FocusManager.instance.primaryFocus);
    if (target == null ||
        !isContextDescendant(target.editable.context, context)) {
      return;
    }
    final scrollable = Scrollable.maybeOf(target.editable.context);
    if (scrollable == null ||
        !isContextDescendant(scrollable.context, context)) {
      return;
    }
    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;

    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    final keyboardTop = MediaQuery.sizeOf(context).height - _imeBottom;
    final safeBottom = math.min(viewportBottom, keyboardTop) - 16.0;
    final safeTop = viewportTop + 8.0;
    if (safeBottom <= safeTop) return;

    final fieldTopLeft = target.box.localToGlobal(target.localRect.topLeft);
    final fieldTop = fieldTopLeft.dy;
    final fieldBottom = fieldTop + target.localRect.height;

    var delta = 0.0;
    if (fieldBottom > safeBottom) {
      delta = fieldBottom - safeBottom;
      if (fieldTop - delta < safeTop &&
          target.localRect.height <= safeBottom - safeTop) {
        delta = math.max(0.0, fieldTop - safeTop);
      }
    } else if (fieldTop < safeTop) {
      delta = fieldTop - safeTop;
    }
    if (delta.abs() <= 1.0) return;

    final targetPixels = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((targetPixels - position.pixels).abs() <= 1.0) return;
    if (identical(_animatingPosition, position) &&
        _animatingTarget != null &&
        (_animatingTarget! - targetPixels).abs() <= 1.0 &&
        position.isScrollingNotifier.value) {
      return;
    }
    final duration = Motion.duration(context, 160);
    if (duration == Duration.zero) {
      _animatingPosition = null;
      _animatingTarget = null;
      position.jumpTo(targetPixels);
    } else {
      _animatingPosition = position;
      _animatingTarget = targetPixels;
      unawaited(
        position
            .animateTo(
              targetPixels,
              duration: duration,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (identical(_animatingPosition, position)) {
                _animatingPosition = null;
                _animatingTarget = null;
              }
            }),
      );
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _controller?.removeListener(_onTextChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          if (_imeBottom > 0) _scheduleReveal();
          return false;
        },
        child: widget.child,
      );
}

/// Width-dependent layouts reuse their widget tree during height-only resizing.
class WidthLayoutBuilder extends StatefulWidget {
  final Widget Function(BuildContext, double) builder;
  const WidthLayoutBuilder({super.key, required this.builder});
  @override
  State<WidthLayoutBuilder> createState() => _WidthLayoutBuilderState();
}

class _WidthLayoutBuilderState extends State<WidthLayoutBuilder> {
  double? width;
  Widget? content;
  @override
  void didUpdateWidget(WidthLayoutBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    content = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    content = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, bounds) {
      if (content == null || width != bounds.maxWidth) {
        width = bounds.maxWidth;
        content = widget.builder(context, bounds.maxWidth);
      }
      return content!;
    },
  );
}

/// Shared action styling, touch feedback and saving state for repeated footers.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary, quiet, busy, destructive;
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.quiet = false,
    this.busy = false,
    this.destructive = false,
  });
  @override
  Widget build(BuildContext context) {
    final action = withFeedback(busy ? null : onPressed);
    final text = SkeletonValue(
      loading: busy,
      semanticsLabel: '$label in progress',
      child: Text(label),
    );
    if (quiet) {
      return TextButton(
        onPressed: action,
        style: destructive
            ? TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        child: text,
      );
    }
    if (secondary) {
      return icon == null
          ? OutlinedButton(onPressed: action, child: text)
          : OutlinedButton.icon(
              onPressed: action,
              icon: Icon(icon, size: 18),
              label: text,
            );
    }
    return icon == null
        ? FilledButton(onPressed: action, child: text)
        : FilledButton.icon(
            onPressed: action,
            icon: Icon(icon, size: 18),
            label: text,
          );
  }
}

/// Consistent sheet title, optional icon and trailing controls.
class PanelHeading extends StatelessWidget {
  final String title;
  final Widget? leading, trailing;
  const PanelHeading({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 14)],
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      ?trailing,
    ],
  );
}

class PanelActions extends StatelessWidget {
  final List<Widget> children;
  const PanelActions({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final short = media.size.height - media.viewInsets.bottom < 560;
    if (short && children.length == 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: children[0]),
          const SizedBox(width: 8),
          Expanded(child: children[1]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

/// Shared depth for app overlays, separate from ordinary content cards.
abstract final class FloatingDepth {
  static const elevation = 16.0;
  static Color color(BuildContext context) => Colors.black.withValues(
    alpha: Theme.of(context).brightness == Brightness.dark ? .48 : .28,
  );
  static List<BoxShadow> shadows(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .38 : .18),
        blurRadius: 28,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .24 : .12),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ];
  }
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final bool floating;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.floating = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: borderRadius,
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
      ),
      boxShadow: floating
          ? FloatingDepth.shadows(context)
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: .018),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Shared Liquid Glass material tokens derived from the bottom PillNavigation.
abstract final class LiquidGlassStyle {
  static const double defaultRadius = 28.0;

  static List<BoxShadow> shadows(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
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
    ];
  }

  static LiquidGlassSettings settings({bool swiping = false}) =>
      LiquidGlassSettings(blur: swiping ? 0 : 18, thickness: swiping ? 8 : 18);

  static BoxDecoration surfaceDecoration(
    BuildContext context, {
    double radius = defaultRadius,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: scheme.surface.withValues(alpha: dark ? .52 : .62),
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? .12 : .55),
        width: 0.8,
      ),
    );
  }
}

class Chrome extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  const Chrome({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = LiquidGlassStyle.defaultRadius,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: LiquidGlassStyle.shadows(context),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: GlassContainer(
        useOwnLayer: true,
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
        settings: LiquidGlassStyle.settings(),
        padding: EdgeInsets.zero,
        child: Container(
          padding: padding,
          decoration: LiquidGlassStyle.surfaceDecoration(
            context,
            radius: borderRadius,
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Circular Liquid Glass icon button with pressed scale feedback matching PillNavigation.
class GlassCircleButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool selected;
  final VoidCallback onPressed;

  const GlassCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.iconSize = 22,
    this.selected = false,
    required this.onPressed,
  });

  @override
  State<GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<GlassCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: AnimatedScale(
      scale: _pressed ? 0.9 : 1.0,
      duration: Motion.duration(context, 120),
      curve: Curves.easeOutCubic,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Chrome(
          borderRadius: 24,
          padding: EdgeInsets.zero,
          child: Semantics(
            selected: widget.selected,
            child: IconButton(
              tooltip: widget.tooltip,
              icon: Icon(widget.icon, size: widget.iconSize),
              onPressed: widget.onPressed,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Anchored choices share the app surface, selection and motion treatment.
Future<T?> showChoiceMenu<T>(
  BuildContext anchor, {
  required Map<T, String> choices,
  required T selected,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final theme = Theme.of(anchor);
  return showMenu<T>(
    context: anchor,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy + box.size.height + 8,
        box.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    ),
    color: theme.colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: FloatingDepth.elevation,
    shadowColor: FloatingDepth.color(anchor),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: theme.colorScheme.onSurface.withValues(alpha: .08),
      ),
    ),
    popUpAnimationStyle: AnimationStyle(
      duration: Motion.duration(anchor, 150),
      reverseDuration: Motion.duration(anchor, 120),
      curve: Motion.curve,
    ),
    items: [
      for (final entry in choices.entries)
        PopupMenuItem<T>(
          value: entry.key,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: entry.key == selected
                  ? theme.colorScheme.onSurface.withValues(alpha: .08)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(entry.value, style: theme.textTheme.bodyMedium),
                ),
                if (entry.key == selected)
                  const Icon(Icons.check_rounded, size: 16),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Loading keeps the value's intrinsic layout and animates only its placeholder.
class SkeletonValue extends StatelessWidget {
  final bool loading;
  final Widget child;
  final String semanticsLabel;
  const SkeletonValue({
    super.key,
    required this.loading,
    required this.child,
    this.semanticsLabel = 'Loading',
  });
  @override
  Widget build(BuildContext context) {
    if (!loading) return child;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Semantics(
      label: semanticsLabel,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Stack(
            children: [
              Opacity(opacity: 0, child: child),
              Positioned.fill(
                child: MediaQuery.disableAnimationsOf(context)
                    ? placeholder
                    : placeholder
                          .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                          .fade(
                            begin: .5,
                            end: 1,
                            duration: const Duration(milliseconds: 900),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared record placeholders for drawers and workspaces awaiting data.
class SkeletonList extends StatelessWidget {
  final bool scrollable;
  final int count;
  const SkeletonList({super.key, this.scrollable = true, this.count = 4});
  @override
  Widget build(BuildContext context) {
    final rows = [
      for (var i = 0; i < count; i++)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: SkeletonValue(
            loading: true,
            child: SizedBox(width: double.infinity, height: 56),
          ),
        ),
    ];
    return Semantics(
      label: 'Loading records',
      child: ExcludeSemantics(
        child: scrollable
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: rows,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: rows,
              ),
      ),
    );
  }
}

/// Shared committed-action wording and icons for the existing top toast pill.
enum DataAction {
  saved('saved', LucideIcons.save),
  updated('updated', LucideIcons.pencilLine),
  deleted('deleted', LucideIcons.trash2),
  started('started', LucideIcons.play),
  ended('ended and saved', LucideIcons.circleCheck),
  duplicated('duplicated', LucideIcons.copy),
  reordered('reordered', LucideIcons.arrowUpDown),
  exported('exported', LucideIcons.download),
  restored('restored', LucideIcons.upload),
  enabled('enabled', LucideIcons.check),
  disabled('disabled', LucideIcons.pause);

  final String verb;
  final IconData icon;
  const DataAction(this.verb, this.icon);
}

void dataToast(BuildContext context, String resource, DataAction action) {
  if (context.mounted) {
    toast(context, '$resource ${action.verb}', icon: action.icon);
  }
}

/// Compact presentation shared by Map timeline and Settings activity logs.
class LogRow extends StatelessWidget {
  final String title, dateTime, details;
  final Widget? leading, action;
  const LogRow({
    super.key,
    required this.title,
    required this.dateTime,
    required this.details,
    this.leading,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Surface(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      minTileHeight: 0,
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: const Border(),
      collapsedShape: const Border(),
      expansionAnimationStyle: AnimationStyle(
        duration: Motion.duration(context, 200),
        reverseDuration: Motion.duration(context, 200),
        curve: Motion.curve,
      ),
      leading: leading,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        dateTime,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            details,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
      ],
    ),
  );
}

/// Paint-only pulse: never rebuilds the map or its saved markers per frame.
class LocationPulse extends StatefulWidget {
  final Color color;
  const LocationPulse({super.key, required this.color});
  @override
  State<LocationPulse> createState() => _LocationPulseState();
}

class _LocationPulseState extends State<LocationPulse>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
      animation.value = .35;
    } else {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _LocationPulsePainter(animation, widget.color),
      size: const Size(48, 48),
    ),
  );
}

class _LocationPulsePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  _LocationPulsePainter(this.animation, this.color) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      10 + animation.value * 13,
      Paint()..color = color.withValues(alpha: .25 * (1 - animation.value)),
    );
    canvas.drawCircle(center, 9, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LocationPulsePainter old) =>
      old.color != color || old.animation != animation;
}
