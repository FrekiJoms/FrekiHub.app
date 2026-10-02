import 'dart:async';

import 'package:flutter/material.dart';
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
      builder: (context, child) =>
          RepaintBoundary(key: ThemeReveal.key, child: child!),
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
  Timer? automationTimer;
  bool startupReady = false;
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
        await ref
            .read(databaseProvider)
            .clockOut(pending['id'] as String, at: pending['ended'] as int);
        await NativeSession.acknowledge();
      }
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not reconcile the notification action: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (startupReady && state == AppLifecycleState.resumed) {
      unawaited(reconcile());
    }
  }

  @override
  void dispose() {
    automationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    ref.listen(dataProvider, (before, after) {
      if (!after.hasValue) return;
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
        unawaited(
          NativeSession.start(
            running,
            todaySeconds: after.value!.sessions
                .where((s) => s.day == running.day && s.ended != null)
                .fold(0, (sum, s) => sum + (s.ended! - s.started) ~/ 1000),
          ).then((ok) {
            if (!ok && mounted) {
              toast(
                context,
                'Timer saved. Enable notifications / Live Activities for the outside-app timer.',
              );
            }
          }),
        );
      }
    });
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
          backgroundColor: Colors.transparent,
          body: GlassScaffold(
            background: const CanvasBackground(),
            edgeFade: false,
            body: SafeArea(
              bottom: false,
              child: async.when(
                data: (data) => Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                        child: AnimatedSwitcher(
                          duration: Motion.duration(c),
                          reverseDuration: Motion.duration(c, 200),
                          switchInCurve: Motion.curve,
                          switchOutCurve: Motion.curve,
                          transitionBuilder: (child, animation) {
                            final incoming = child.key == ValueKey(index);
                            return IgnorePointer(
                              ignoring: !incoming,
                              child: TickerMode(
                                enabled: incoming,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: Offset(
                                        (incoming ? 1 : -1) *
                                            slideDirection *
                                            .12,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(index),
                            child: switch (index) {
                              0 => TodayScreen(data: data),
                              1 => CalendarScreen(data: data),
                              2 => HistoryScreen(data: data),
                              3 => BudgetScreen(data: data),
                              _ => SettingsScreen(data: data),
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.paddingOf(c).bottom + 12,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: PillNavigation(
                            index: index,
                            onQuickAdd: (kind) => openQuickAdd(
                              c,
                              data,
                              dayKey(DateTime.now()),
                              kind,
                            ),
                            onChanged: (i) {
                              if (i == index) return;
                              ActionFeedback.tap(transition: true);
                              setState(() {
                                slideDirection = i > index ? 1 : -1;
                                index = i;
                                lastTab = i;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SizedBox.square(
                        dimension: 48,
                        child: GlassContainer(
                          useOwnLayer: true,
                          shape: const LiquidOval(),
                          settings: const LiquidGlassSettings(
                            blur: 12,
                            thickness: 24,
                          ),
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
