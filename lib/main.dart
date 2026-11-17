import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'data.dart';
import 'app_update.dart';
import 'automation_sync.dart';
import 'design.dart';
import 'screens.dart';
import 'services.dart';
import 'theme_reveal.dart';
import 'startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      child: LiquidGlassWidgets.wrap(
        brightnessResolver: Theme.maybeBrightnessOf,
        adaptiveQuality: true,
        child: const FrekiHubApp(),
      ),
    ),
  );
}

final _router = GoRouter(
  observers: [FeedbackNavigatorObserver()],
  routes: [GoRoute(path: '/', builder: (c, s) => const AppShell())],
);

class FrekiHubApp extends ConsumerWidget {
  const FrekiHubApp({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final mode = ref.watch(
      dataProvider.select((data) => data.value?.prefs['theme'] ?? 'system'),
    );
    ActionFeedback.soundEnabled = ref.watch(
      dataProvider.select((data) => data.value?.prefs['sound'] == 'true'),
    );
    return MaterialApp.router(
      title: 'FrekiHub',
      debugShowCheckedModeBanner: false,
      theme: Design.theme(false),
      darkTheme: Design.theme(true),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: _router,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => KeyboardOverlay(
        child: RepaintBoundary(key: ThemeReveal.key, child: child!),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int index = 0;
  int lastTab = 0;
  double slideDirection = 1;
  String? lastRunning;
  int? savedPage;
  Timer? automationTimer;
  bool startupReady = false;
  bool _updateChecked = false;
  late final PageController _tabController = PageController(initialPage: 0);
  late final AnimationController _jumpFadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1.0,
  );
  bool _tabAnimating = false;
  bool _pageScrolling = false;
  final ValueNotifier<bool> _swiping = ValueNotifier<bool>(false);
  final ValueNotifier<int> _activeTab = ValueNotifier<int>(0);
  AppData? _tabsData;
  List<Widget>? _tabPages;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController.addListener(_onPageScroll);
    automationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (startupReady &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(reconcile());
      }
    });
  }

  void _onPageScroll() {
    if (!_tabController.hasClients) return;
    final page = _tabController.page ?? _tabController.initialPage.toDouble();
    final scrolling = (page - page.roundToDouble()).abs() > 0.002;
    if (scrolling != _pageScrolling) {
      _pageScrolling = scrolling;
      _swiping.value = scrolling;
    }
  }

  Future<void> _checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    final url = AppUpdater.configuredUrl;
    if (url.isEmpty) return;
    try {
      final current = await AppUpdater.currentVersion();
      if (current == null || !mounted) return;
      final info = await AppUpdater.check(url);
      if (info != null && info.versionCode > current.versionCode && mounted) {
        await AppUpdater.showUpdateSheet(context, info, current: current);
      }
    } catch (_) {
      // Startup update check stays silent when offline or unavailable.
    }
  }

  Future<void> reconcile() async {
    try {
      await AutomationSync.reconcile(ref.read(databaseProvider));
      final db = ref.read(databaseProvider);
      final prefs = await db.readPreferences();
      for (final notice in prefs.entries.where(
        (p) => p.key.startsWith('ruleToast:'),
      )) {
        if (mounted) toast(context, notice.value);
        await (db.delete(
          db.preferences,
        )..where((p) => p.key.equals(notice.key))).go();
      }
      final destination = await NativeSession.channel.invokeMethod<String>(
        'purchaseDestination',
      );
      if (destination == 'budget' && mounted) {
        unawaited(_goToTab(3));
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Could not sync the notification action. Your pending actions will retry.',
          error: true,
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      NativeSession.channel
          .invokeMethod(
            'automationAppState',
            state == AppLifecycleState.resumed,
          )
          .catchError((Object _) {}),
    );
    if (startupReady && state == AppLifecycleState.resumed) {
      unawaited(reconcile().then((_) => mounted ? retrySessionTimer() : null));
    }
  }

  List<Widget> _buildTabPages(AppData data) {
    if (!identical(_tabsData, data) || _tabPages == null) {
      _tabsData = data;
      _tabPages = [
        RepaintBoundary(
          child: _KeepAliveTab(
            tabIndex: 0,
            activeTab: _activeTab,
            child: TodayScreen(data: data),
          ),
        ),
        RepaintBoundary(
          child: _KeepAliveTab(
            tabIndex: 1,
            activeTab: _activeTab,
            child: _DeferredTab(
              tabIndex: 1,
              activeTab: _activeTab,
              delay: const Duration(milliseconds: 250),
              builder: () => MapScreen(data: data),
            ),
          ),
        ),
        RepaintBoundary(
          child: _KeepAliveTab(
            tabIndex: 2,
            activeTab: _activeTab,
            child: _DeferredTab(
              tabIndex: 2,
              activeTab: _activeTab,
              delay: const Duration(milliseconds: 120),
              builder: () => HistoryScreen(data: data),
            ),
          ),
        ),
        RepaintBoundary(
          child: _KeepAliveTab(
            tabIndex: 3,
            activeTab: _activeTab,
            child: _DeferredTab(
              tabIndex: 3,
              activeTab: _activeTab,
              delay: const Duration(milliseconds: 120),
              builder: () => BudgetScreen(data: data),
            ),
          ),
        ),
      ];
    }
    return _tabPages!;
  }

  Future<void> _goToTab(int i) async {
    if (i < 0 || i > 3) return;
    final fromOverlay = index >= 4;
    final currentTab = index <= 3 ? index : lastTab;
    if (!fromOverlay && i == currentTab) return;
    ActionFeedback.tap(transition: true);
    final distance = (i - currentTab).abs();
    _swiping.value = true;

    if (!_tabController.hasClients) {
      if (!mounted) return;
      setState(() {
        slideDirection = i > currentTab ? 1 : -1;
        index = i;
        lastTab = i;
      });
      _activeTab.value = i;
      _swiping.value = false;
      return;
    }

    if (!mounted) return;
    setState(() {
      slideDirection = i > currentTab ? 1 : -1;
      index = i;
      lastTab = i;
    });
    _activeTab.value = i;

    _tabAnimating = true;
    try {
      if (distance <= 1) {
        await _tabController.animateToPage(
          i,
          duration: Motion.duration(context, 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        await _jumpFadeController.reverse(from: 1.0);
        _tabController.jumpToPage(i);
        await _jumpFadeController.forward(from: 0.0);
      }
    } finally {
      _tabAnimating = false;
      _swiping.value = false;
    }
  }

  @override
  void dispose() {
    automationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onPageScroll);
    _tabController.dispose();
    _jumpFadeController.dispose();
    _swiping.dispose();
    _activeTab.dispose();
    super.dispose();
  }

  Future<void> syncSessionTimer(Session running) async {
    try {
      if (!await NativeSession.cache(running) || !mounted) return;
      if (ref.read(dataProvider).value?.running?.id != running.id) return;
      final ok = await PermissionHints.perform<bool>(
        context,
        'start',
        () async {
          if (!mounted ||
              ref.read(dataProvider).value?.running?.id != running.id) {
            return null;
          }
          return NativeSession.start(running);
        },
      );
      if (ok == false && mounted) {
        toast(
          context,
          'Timer saved. Enable notifications / Live Activities for the outside-app timer.',
        );
      }
    } catch (_) {
      if (mounted) {
        toast(
          context,
          'Timer saved. Could not request notification access.',
          error: true,
        );
      }
    }
  }

  Future<void> retrySessionTimer() async {
    try {
      final status = await AutomationSync.status();
      if (!mounted) return;
      final running = ref.read(dataProvider).value?.running;
      if (mounted && running != null && status['timer_available'] == false) {
        await syncSessionTimer(running);
      }
    } on PlatformException {
      // Reconciliation retains its separate retry/error presentation.
    } on MissingPluginException {
      // Native timer delivery is unavailable in desktop previews.
    }
  }

  @override
  Widget build(BuildContext c) {
    ref.listen(dataProvider, (before, after) {
      if (!after.hasValue) return;
      if ((after.value!.prefs['automation'] ?? '').contains('"source"')) {
        unawaited(
          AutomationSync.configure(after.value!).catchError((Object _) {}),
        );
      }
      final running = after.value?.running;
      final signature = running == null
          ? null
          : '${running.id}:${running.started}';
      if (signature == lastRunning) {
        return;
      }
      lastRunning = signature;
      if (running == null) {
        unawaited(NativeSession.stop());
      } else {
        unawaited(syncSessionTimer(running));
      }
    });
    if (savedPage != index) {
      savedPage = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref
                .read(databaseProvider)
                .pref(
                  'currentPage',
                  [
                    'session_page',
                    'map_page',
                    'sessions_page',
                    'budget_page',
                    'settings_page',
                    'calendar_page',
                  ][index],
                )
                .catchError((Object _) {}),
          );
        }
      });
    }
    final async = ref.watch(dataProvider);
    final graphics = ref.watch(graphicsProvider);
    if (async.hasError && !async.hasValue) {
      return Scaffold(
        body: StartupLoading(
          stage: async.error is TimeoutException
              ? 'Your records are taking longer to open'
              : 'Your records could not be opened',
          failed: true,
          onRetry: () => ref.invalidate(dataProvider),
        ),
      );
    }
    if (!graphics.hasValue || (!async.hasValue && async.isLoading)) {
      return Scaffold(
        body: StartupLoading(
          stage: graphics.hasError
              ? 'Could not prepare the interface'
              : graphics.hasValue
              ? 'Opening your records'
              : 'Preparing your space',
          failed: graphics.hasError,
          onRetry: () => ref.invalidate(graphicsProvider),
        ),
      );
    }
    if (!startupReady && async.hasValue) {
      startupReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(reconcile());
          unawaited(_checkForUpdate());
        }
      });
    }
    final activeTabIndex = index <= 3 ? index : lastTab;
    if (_activeTab.value != activeTabIndex) _activeTab.value = activeTabIndex;
    return ValueListenableBuilder<bool>(
      valueListenable: _swiping,
      builder: (context, swiping, child) => GlassAccessibilityScope(
        reduceTransparency: (graphics.value == true && !swiping) ? null : true,
        child: child!,
      ),
      child: StartupIntro(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          body: GlassScaffold(
            resizeToAvoidBottomInset: false,
            background: const CanvasBackground(),
            edgeFade: false,
            body: SafeArea(
              bottom: false,
              child: async.when(
                data: (data) => Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _jumpFadeController,
                            curve: Curves.easeOut,
                          ),
                          child: TickerMode(
                            enabled: index < 4,
                            child: IgnorePointer(
                              ignoring: index >= 4,
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.depth != 0) return false;
                                  if (n is ScrollStartNotification) {
                                    _swiping.value = true;
                                  } else if (n is ScrollEndNotification) {
                                    _swiping.value = false;
                                    final settled = _tabController.hasClients
                                        ? (_tabController.page?.round() ??
                                              lastTab)
                                        : lastTab;
                                    final currentTab = index <= 3
                                        ? index
                                        : lastTab;
                                    if (settled != currentTab &&
                                        !_tabAnimating) {
                                      setState(() {
                                        slideDirection = settled > currentTab
                                            ? 1
                                            : -1;
                                        index = settled;
                                        lastTab = settled;
                                      });
                                    }
                                  }
                                  return false;
                                },
                                child: PageView(
                                  controller: _tabController,
                                  physics: index >= 4
                                      ? const NeverScrollableScrollPhysics()
                                      : const ClampingScrollPhysics(),
                                  onPageChanged: (_) {},
                                  children: _buildTabPages(data),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: index < 4,
                        child: AnimatedSwitcher(
                          duration: Motion.duration(c),
                          reverseDuration: Motion.duration(c, 220),
                          switchInCurve: Motion.curve,
                          switchOutCurve: Motion.curve,
                          transitionBuilder: (child, animation) {
                            if (child.key == const ValueKey('none')) {
                              return const SizedBox.shrink();
                            }
                            final edgeX = child.key == const ValueKey(5)
                                ? -0.08
                                : 0.08;
                            return IgnorePointer(
                              ignoring: child.key != ValueKey(index),
                              child: FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(edgeX, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: index >= 4
                              ? ColoredBox(
                                  key: ValueKey(index),
                                  color: Theme.of(c).scaffoldBackgroundColor,
                                  child: index == 5
                                      ? CalendarScreen(data: data)
                                      : SettingsScreen(data: data),
                                )
                              : const SizedBox.shrink(key: ValueKey('none')),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.viewPaddingOf(c).bottom + 12,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: PillNavigation(
                            index: index <= 3 ? index : lastTab,
                            tabController: _tabController,
                            swiping: _swiping,
                            onQuickAdd: (kind) => openQuickAdd(
                              c,
                              data,
                              dayKey(DateTime.now()),
                              kind,
                            ),
                            onChanged: _goToTab,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: GlassCircleButton(
                        tooltip: index == 5 ? 'Close calendar' : 'Calendar',
                        icon: LucideIcons.calendarDays,
                        selected: index == 5,
                        onPressed: () {
                          ActionFeedback.tap(transition: true);
                          setState(() {
                            slideDirection = index == 5 ? 1 : -1;
                            index = index == 5 ? lastTab : 5;
                          });
                        },
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GlassCircleButton(
                        tooltip: index == 4 ? 'Close settings' : 'Settings',
                        icon: LucideIcons.settings2,
                        selected: index == 4,
                        onPressed: () {
                          ActionFeedback.tap(transition: true);
                          setState(() {
                            slideDirection = index == 4 ? -1 : 1;
                            index = index == 4 ? lastTab : 4;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                loading: () =>
                    const StartupLoading(stage: 'Opening your records'),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Your data could not be opened.'),
                        const SizedBox(height: 16),
                        Text('$e'),
                        TextButton(
                          onPressed: withFeedback(
                            () => ref.invalidate(dataProvider),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final int tabIndex;
  final ValueListenable<int> activeTab;
  final Widget child;
  const _KeepAliveTab({
    required this.tabIndex,
    required this.activeTab,
    required this.child,
  });

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<int>(
      valueListenable: widget.activeTab,
      builder: (context, active, child) =>
          TickerMode(enabled: active == widget.tabIndex, child: child!),
      child: widget.child,
    );
  }
}

class _DeferredTab extends StatefulWidget {
  final int tabIndex;
  final ValueListenable<int> activeTab;
  final Duration delay;
  final Widget Function() builder;
  const _DeferredTab({
    required this.tabIndex,
    required this.activeTab,
    required this.delay,
    required this.builder,
  });

  @override
  State<_DeferredTab> createState() => _DeferredTabState();
}

class _DeferredTabState extends State<_DeferredTab> {
  bool _built = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(covariant _DeferredTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      oldWidget.activeTab.removeListener(_check);
      widget.activeTab.addListener(_check);
      _check();
    }
  }

  void _check() {
    if (_built || !mounted) return;
    if (widget.activeTab.value == widget.tabIndex) {
      _timer ??= Timer(widget.delay, () {
        _timer = null;
        if (mounted && !_built) {
          setState(() => _built = true);
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_check);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_built) return widget.builder();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: const SizedBox.expand(),
    );
  }
}
