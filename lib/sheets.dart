part of 'design.dart';

Future<T?> panel<T>(
  BuildContext context,
  Widget child, {
  bool scrollable = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 640),
  sheetAnimationStyle: AnimationStyle(
    duration: Motion.duration(context, 250),
    reverseDuration: Motion.duration(context, 150),
  ),
  builder: (_) =>
      _PanelSheet(child: scrollable ? PanelContent(child: child) : child),
);

/// Fixed header/actions around one body that coordinates scrolling and resizing.
/// Plain content gets a scroll wrapper. For a lazy ListView, pass scrollable:true.
class PanelContent extends StatelessWidget {
  final Widget child;
  final Widget? header, footer;
  final bool scrollable;
  final EdgeInsets padding;
  const PanelContent({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.scrollable = false,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    _PanelScope.maybeOf(context)?.measureAfterLayout();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(padding: const EdgeInsets.only(bottom: 16), child: header),
          Expanded(
            child: scrollable
                ? child
                : SingleChildScrollView(primary: true, child: child),
          ),
          if (footer != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: footer),
        ],
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String detail, {
  String action = 'Delete',
}) async =>
    await panel<bool>(
      context,
      Builder(
        builder: (context) => PanelContent(
          header: PanelHeading(title: title),
          footer: PanelActions(
            children: [
              AppButton(
                label: action,
                onPressed: () => Navigator.pop(context, true),
              ),
              AppButton(
                label: 'Cancel',
                secondary: true,
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          child: Text(detail),
        ),
      ),
    ) ??
    false;

class _PanelScope extends InheritedWidget {
  final VoidCallback measureAfterLayout;
  const _PanelScope({required this.measureAfterLayout, required super.child});
  static _PanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelScope>();
  @override
  bool updateShouldNotify(_PanelScope oldWidget) => false;
}

class _PanelSheet extends StatefulWidget {
  final Widget child;
  const _PanelSheet({required this.child});
  @override
  State<_PanelSheet> createState() => _PanelSheetState();
}

class _PanelSheetState extends State<_PanelSheet> {
  static const expanded = .70;
  final controller = DraggableScrollableController();
  ScrollController? bodyScroll;
  double defaultExtent = expanded, availableHeight = 0, layoutHeight = 0;
  double keyboard = 0, dragStart = 0;
  bool measured = false, measurePending = false, dragging = false;

  void measureAfterLayout() {
    if (measurePending) return;
    measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      measurePending = false;
      if (!mounted || !controller.isAttached || availableHeight == 0) return;
      final scroll = bodyScroll;
      double? contentHeight;
      if (scroll != null && scroll.positions.length == 1) {
        final root = scroll.position.context.notificationContext
            ?.findRenderObject();
        void visit(RenderObject object) {
          if (contentHeight != null) return;
          if (object is RenderBox && object is RenderAbstractViewport) {
            var extent = 0.0;
            object.visitChildren((child) {
              if (child is RenderSliver) {
                extent += child.geometry?.scrollExtent ?? 0;
              }
              if (child is RenderBox && child.hasSize) {
                extent += child.size.height;
              }
            });
            contentHeight = layoutHeight - object.size.height + extent;
          } else {
            object.visitChildren(visit);
          }
        }

        if (root != null) visit(root);
      }
      final next =
          ((contentHeight ?? availableHeight * expanded) / availableHeight)
              .clamp(math.min(120.0 / availableHeight, expanded), expanded)
              .toDouble();
      final previous = defaultExtent;
      final first = !measured;
      if (first || (next - previous).abs() > .001) {
        setState(() {
          defaultExtent = next;
          measured = true;
        });
        if (first) {
          controller.jumpTo(keyboard > 0 ? expanded : next);
        } else if (!dragging &&
            keyboard == 0 &&
            controller.size <= previous + .001) {
          settle(next);
        }
      }
    });
  }

  void settle(double extent) {
    if (!controller.isAttached) return;
    final duration = Motion.duration(context);
    if (duration == Duration.zero) {
      controller.jumpTo(extent);
    } else {
      unawaited(
        controller.animateTo(extent, duration: duration, curve: Motion.curve),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.viewInsetsOf(context).bottom;
    if (next > keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) settle(expanded);
      });
    }
    keyboard = next;
    measureAfterLayout();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: LayoutBuilder(
      builder: (context, bounds) {
        availableHeight = bounds.maxHeight;
        measureAfterLayout();
        return DraggableScrollableSheet(
          controller: controller,
          initialChildSize: expanded,
          minChildSize: 0,
          maxChildSize: expanded,
          snap: true,
          snapSizes: defaultExtent < expanded - .001 ? [defaultExtent] : null,
          shouldCloseOnMinExtent: true,
          expand: false,
          snapAnimationDuration: MediaQuery.disableAnimationsOf(context)
              ? const Duration(milliseconds: 1)
              : Motion.duration(context, 150),
          builder: (context, scroll) {
            bodyScroll = scroll;
            return Opacity(
              opacity: measured ? 1 : 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, extentBounds) {
                    // Retain a valid layout while the visible sheet is dragged closed.
                    layoutHeight = math.max(
                      defaultExtent * availableHeight,
                      extentBounds.maxHeight,
                    );
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: layoutHeight,
                        maxHeight: layoutHeight,
                        child: Column(
                          children: [
                            Semantics(
                              label: 'Resize sheet',
                              button: true,
                              onIncrease: () => settle(expanded),
                              onDecrease: () => settle(
                                controller.size <= defaultExtent + .001
                                    ? 0
                                    : defaultExtent,
                              ),
                              customSemanticsActions: {
                                const CustomSemanticsAction(
                                  label: 'Close sheet',
                                ): () =>
                                    settle(0),
                              },
                              child: GestureDetector(
                                key: const ValueKey('panel-drag-handle'),
                                behavior: HitTestBehavior.opaque,
                                onTap: withFeedback(
                                  () => settle(
                                    controller.size < expanded - .001
                                        ? expanded
                                        : defaultExtent,
                                  ),
                                ),
                                onVerticalDragStart: (_) {
                                  dragging = true;
                                  dragStart = controller.size;
                                },
                                onVerticalDragUpdate: (details) {
                                  if (controller.isAttached) {
                                    controller.jumpTo(
                                      (controller.size -
                                              details.delta.dy /
                                                  availableHeight)
                                          .clamp(0.0, expanded),
                                    );
                                  }
                                },
                                onVerticalDragEnd: (details) {
                                  dragging = false;
                                  final velocity = details.primaryVelocity ?? 0;
                                  if (velocity > 650 ||
                                      controller.size < defaultExtent * .55 ||
                                      (velocity > 250 &&
                                          dragStart <= defaultExtent + .001)) {
                                    settle(0);
                                  } else if (velocity < -250) {
                                    settle(expanded);
                                  } else if (velocity > 250) {
                                    settle(defaultExtent);
                                  } else {
                                    settle(
                                      controller.size <
                                              (defaultExtent + expanded) / 2
                                          ? defaultExtent
                                          : expanded,
                                    );
                                  }
                                },
                                onVerticalDragCancel: () {
                                  dragging = false;
                                },
                                child: SizedBox(
                                  height: 40,
                                  width: double.infinity,
                                  child: Center(
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: .35),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: RepaintBoundary(
                                child: PrimaryScrollController(
                                  controller: scroll,
                                  automaticallyInheritForPlatforms:
                                      TargetPlatform.values.toSet(),
                                  child: _PanelScope(
                                    measureAfterLayout: measureAfterLayout,
                                    child:
                                        NotificationListener<
                                          ScrollMetricsNotification
                                        >(
                                          onNotification: (_) {
                                            measureAfterLayout();
                                            return false;
                                          },
                                          child: widget.child,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
