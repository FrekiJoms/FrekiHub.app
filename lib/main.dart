import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'data.dart';
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
    with WidgetsBindingObserver {
  int index = 0;
  int lastTab = 0;
  double slideDirection = 1;
  String? lastRunning;
  int? savedPage;
  Timer? automationTimer;
  bool startupReady = false;
  late final PageController _tabController = PageController(initialPage: 0);
  bool _tabAnimating = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    automationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (startupReady &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(reconcile());
      }
    });
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
        setState(() {
          slideDirection = index > 3 ? -1 : 1;
          index = 3;
          lastTab = 3;
        });
      }
      final pending = await NativeSession.pending();
      if (pending != null) {
        await NativeSession.applyPending(ref.read(databaseProvider), pending);
        await NativeSession.acknowledge();
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

  void _goToTab(int i, {bool animate = true}) {
    if (i < 0 || i > 3) return;
    final fromOverlay = index >= 4;
    final currentTab = index <= 3 ? index : lastTab;
    if (!fromOverlay && i == currentTab) return;
    ActionFeedback.tap(transition: true);
    setState(() {
      slideDirection = i > currentTab ? 1 : -1;
      index = i;
      lastTab = i;
    });
    if (animate && _tabController.hasClients) {
      _tabAnimating = true;
      _tabController
          .animateToPage(
            i,
            duration: Motion.duration(context, 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _tabAnimating = false);
    } else if (_tabController.hasClients) {
      _tabController.jumpToPage(i);
    }
  }

  @override
  void dispose() {
    automationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
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
        if (mounted) unawaited(reconcile());
      });
    }
    return GlassAccessibilityScope(
      reduceTransparency: graphics.value == true ? null : true,
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
                        child: PageView(
                          controller: _tabController,
                          physics: index >= 4
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(parent: ClampingScrollPhysics()),
                          onPageChanged: (i) {
                            if (_tabAnimating) return;
                            if (i == (index <= 3 ? index : lastTab)) return;
                            setState(() {
                              final currentTab = index <= 3 ? index : lastTab;
                              slideDirection = i > currentTab ? 1 : -1;
                              index = i;
                              lastTab = i;
                            });
                          },
                          children: [
                            _KeepAlivePage(
                              active: (index <= 3 ? index : lastTab) == 0,
                              child: TodayScreen(data: data),
                            ),
                            _KeepAlivePage(
                              active: (index <= 3 ? index : lastTab) == 1,
                              child: MapScreen(data: data),
                            ),
                            _KeepAlivePage(
                              active: (index <= 3 ? index : lastTab) == 2,
                              child: HistoryScreen(data: data),
                            ),
                            _KeepAlivePage(
                              active: (index <= 3 ? index : lastTab) == 3,
                              child: BudgetScreen(data: data),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: index < 4,
                        child: AnimatedSwitcher(
                          duration: Motion.duration(c),
                          reverseDuration: Motion.duration(c, 200),
                          switchInCurve: Motion.curve,
                          switchOutCurve: Motion.curve,
                          transitionBuilder: (child, animation) {
                            final incoming = child.key != const ValueKey('none');
                            return IgnorePointer(
                              ignoring: !incoming,
                              child: FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(
                                      (incoming ? 1 : -1) * slideDirection * .12,
                                      0,
                                    ),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: index >= 4
                              ? KeyedSubtree(
                                  key: ValueKey(index),
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
                      child: SizedBox.square(
                        dimension: 48,
                        child: Chrome(
                          padding: EdgeInsets.zero,
                          child: Semantics(
                            selected: index == 5,
                            child: IconButton(
                              tooltip: index == 5
                                  ? 'Close calendar'
                                  : 'Calendar',
                              icon: const Icon(
                                LucideIcons.calendarDays,
                                size: 22,
                              ),
                              onPressed: () {
                                ActionFeedback.tap(transition: true);
                                setState(() {
                                  slideDirection = index == 5 ? 1 : -1;
                                  index = index == 5 ? lastTab : 5;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Chrome(
                          padding: EdgeInsets.zero,
                          child: Semantics(
                            selected: index == 4,
                            child: IconButton(
                              tooltip: index == 4
                                  ? 'Close settings'
                                  : 'Settings',
                              icon: const Icon(LucideIcons.settings2, size: 22),
                              onPressed: () {
                                ActionFeedback.tap(transition: true);
                                setState(() {
                                  slideDirection = index == 4 ? -1 : 1;
                                  index = index == 4 ? lastTab : 4;
                                });
                              },
                            ),
                          ),
                        ),
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

class _KeepAlivePage extends StatefulWidget {
  final bool active;
  final Widget child;
  const _KeepAlivePage({required this.active, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      enabled: widget.active,
      child: widget.child,
    );
  }
}
