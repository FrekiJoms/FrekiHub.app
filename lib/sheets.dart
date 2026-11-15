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
    final scope = _PanelScope.maybeOf(context);
    scope?.measureAfterLayout();
    final clearance = scope?.bodyClearance ?? 0.0;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(padding: const EdgeInsets.only(bottom: 16), child: header),
          Expanded(
            key: scope?.bodyKey,
            child: KeyboardFocusRevealer(
              child: scrollable
                  ? child
                  : SingleChildScrollView(
                      primary: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          KeyedSubtree(key: scope?.contentKey, child: child),
                          if (clearance > 0) SizedBox(height: clearance),
                        ],
                      ),
                    ),
            ),
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
  final GlobalKey bodyKey;
  final GlobalKey contentKey;
  final double bodyClearance;
  const _PanelScope({
    required this.measureAfterLayout,
    required this.bodyKey,
    required this.contentKey,
    required this.bodyClearance,
    required super.child,
  });
  static _PanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelScope>();
  @override
  bool updateShouldNotify(_PanelScope oldWidget) =>
      bodyClearance != oldWidget.bodyClearance ||
      bodyKey != oldWidget.bodyKey ||
      contentKey != oldWidget.contentKey;
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
  final GlobalKey _frameKey = GlobalKey();
  final GlobalKey _sheetKey = GlobalKey();
  final GlobalKey _bodyKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  ScrollController? bodyScroll;
  double defaultExtent = expanded, availableHeight = 0, layoutHeight = 0;
  double dragStart = 0;
  double _imeBottom = 0, _lift = 0, _bodyClearance = 0;
  bool measured = false, measurePending = false, dragging = false;
  bool _lifted = false, _keyboardPending = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onKeyboardInputsChanged);
    controller.addListener(_onKeyboardInputsChanged);
  }

  void _onKeyboardInputsChanged() {
    _scheduleKeyboardGeometry();
  }

  void _scheduleKeyboardGeometry() {
    if (_keyboardPending || !mounted) return;
    _keyboardPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardPending = false;
      _updateKeyboardGeometry();
    });
  }

  void _updateKeyboardGeometry() {
    if (!mounted) return;
    if (_imeBottom <= 0) {
      if (_lift != 0 || _bodyClearance != 0 || _lifted) {
        setState(() {
          _lift = 0;
          _bodyClearance = 0;
          _lifted = false;
        });
      }
      return;
    }
    final target = focusedEditableTarget(FocusManager.instance.primaryFocus);
    if (target == null ||
        !isContextDescendant(
          target.editable.context,
          _sheetKey.currentContext,
        )) {
      if (_lift != 0 || _bodyClearance != 0 || _lifted) {
        setState(() {
          _lift = 0;
          _bodyClearance = 0;
          _lifted = false;
        });
      }
      return;
    }
    final frameBox = _frameKey.currentContext?.findRenderObject() as RenderBox?;
    final sheetBox = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (frameBox == null ||
        sheetBox == null ||
        !frameBox.hasSize ||
        !sheetBox.hasSize) {
      return;
    }

    final frameOrigin = frameBox.localToGlobal(Offset.zero);
    final unLiftedSheetBottom = frameOrigin.dy + frameBox.size.height;
    final unLiftedSheetTop = unLiftedSheetBottom - sheetBox.size.height;
    final areaTop = unLiftedSheetBottom - availableHeight;
    final localTopLeft = target.box.localToGlobal(
      Offset.zero,
      ancestor: sheetBox,
    );
    final unLiftedTargetBottom =
        unLiftedSheetTop + localTopLeft.dy + target.localRect.bottom;
    final keyboardTop = MediaQuery.sizeOf(context).height - _imeBottom;
    final maxLift = math.max(0.0, unLiftedSheetTop - (areaTop + 8.0));
    final obscured = unLiftedTargetBottom > keyboardTop - 16.0;
    final nextLifted = _lifted || obscured;
    final nextLift = nextLifted
        ? (unLiftedSheetBottom - keyboardTop).clamp(0.0, maxLift)
        : 0.0;

    var nextClearance = 0.0;
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (nextLifted && bodyBox != null && bodyBox.hasSize) {
      final localBodyBottom = bodyBox
          .localToGlobal(Offset(0, bodyBox.size.height), ancestor: sheetBox)
          .dy;
      final liftedBodyBottom = (unLiftedSheetTop - nextLift) + localBodyBottom;
      nextClearance = math.max(0.0, liftedBodyBottom - (keyboardTop - 16.0));
    }

    if ((nextLift - _lift).abs() > 0.5 ||
        (nextClearance - _bodyClearance).abs() > 0.5 ||
        nextLifted != _lifted) {
      setState(() {
        _lifted = nextLifted;
        _lift = nextLift;
        _bodyClearance = nextClearance;
      });
    }
  }

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
            final contentBox = _contentKey.currentContext?.findRenderObject();
            if (contentBox is RenderBox && contentBox.hasSize) {
              contentHeight =
                  layoutHeight - object.size.height + contentBox.size.height;
              return;
            }
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
          controller.jumpTo(next);
        } else if (!dragging && controller.size <= previous + .001) {
          settle(next);
        }
        _scheduleKeyboardGeometry();
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
    final nextIme = KeyboardOverlay.imeBottomOf(context);
    if ((nextIme - _imeBottom).abs() > 0.5) {
      _imeBottom = nextIme;
      _scheduleKeyboardGeometry();
    }
    measureAfterLayout();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onKeyboardInputsChanged);
    controller.removeListener(_onKeyboardInputsChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: _frameKey,
    child: LayoutBuilder(
      builder: (context, bounds) {
        availableHeight = bounds.maxHeight;
        measureAfterLayout();
        return Transform.translate(
          offset: Offset(0, -_lift),
          child: DraggableScrollableSheet(
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
                  key: _sheetKey,
                  elevation: FloatingDepth.elevation,
                  shadowColor: FloatingDepth.color(context),
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
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity > 650 ||
                                        controller.size < defaultExtent * .55 ||
                                        (velocity > 250 &&
                                            dragStart <=
                                                defaultExtent + .001)) {
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
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
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
                                      bodyKey: _bodyKey,
                                      contentKey: _contentKey,
                                      bodyClearance: _bodyClearance,
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
          ),
        );
      },
    ),
  );
}
