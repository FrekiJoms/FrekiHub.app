part of 'design.dart';

/// Keeps keyboard metric changes confined to the page viewport.
class KeyboardViewport extends StatelessWidget {
  final Widget child;
  const KeyboardViewport({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}

/// Retains the position of bottom chrome while the keyboard covers it, without
/// painting its glass effects or ticking its animations behind the keyboard.
class KeyboardVisibility extends StatelessWidget {
  final Widget child;
  const KeyboardVisibility({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final visible = MediaQuery.viewInsetsOf(context).bottom == 0;
    return TickerMode(
      enabled: visible,
      child: Visibility(
        visible: visible,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: child,
      ),
    );
  }
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
    final text = Text(busy ? 'Saving…' : label);
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

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: borderRadius,
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
      borderRadius: borderRadius,
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
