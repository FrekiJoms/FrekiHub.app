import 'dart:math' as math;
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'design.dart';

final graphicsProvider = FutureProvider<void>((ref) async {
  // Show the lightweight first frame before loading glass shaders. The database
  // opens concurrently through dataProvider; neither needs a splash delay.
  await WidgetsBinding.instance.endOfFrame;
  final task = TimelineTask()..start('FrekiHub.prepareGraphics');
  try {
    await LiquidGlassWidgets.initialize(
      enablePerformanceMonitor: false,
      warmUpMode: GlassWarmUpMode.never,
    );
  } finally {
    task.finish();
  }
});

class StartupLoading extends StatefulWidget {
  final String stage;
  final bool failed;
  final VoidCallback? onRetry;
  const StartupLoading({
    super.key,
    required this.stage,
    this.failed = false,
    this.onRetry,
  });
  @override
  State<StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<StartupLoading>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotion();
  }

  @override
  void didUpdateWidget(StartupLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncMotion();
  }

  void syncMotion() {
    if (widget.failed || MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
    } else if (!pulse.isAnimating) {
      pulse.repeat();
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: SizedBox.square(
                  dimension: 96,
                  child: CustomPaint(
                    painter: _OrbitPainter(
                      pulse,
                      colors.primary,
                      colors.outlineVariant,
                    ),
                    child: Center(
                      child: Text(
                        'F',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'FrekiHub',
                style: Theme.of(c).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: AnimatedSwitcher(
                  duration: Motion.duration(c, 150),
                  child: Text(
                    widget.stage,
                    key: ValueKey(widget.stage),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
              if (widget.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('Retry'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Animation<double> phase;
  final Color active, track;
  _OrbitPainter(this.phase, this.active, this.track) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = track);
    final start = phase.value * math.pi * 2 - math.pi / 2;
    final sweep =
        math.pi * (.4 + .3 * (1 - math.cos(phase.value * math.pi * 2)));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      paint..color = active,
    );
    for (var i = 0; i < 3; i++) {
      final angle = start - i * .22;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        2.5 - i * .5,
        Paint()..color = active.withValues(alpha: 1 - i * .25),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.active != active || old.track != track || old.phase != phase;
}

class StartupIntro extends StatefulWidget {
  final Widget child;
  const StartupIntro({super.key, required this.child});
  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro>
    with SingleTickerProviderStateMixin {
  late final intro = AnimationController(vsync: this);
  late final curve = CurvedAnimation(parent: intro, curve: Motion.curve);
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      intro.value = 1;
    } else if (!started) {
      intro.duration = Motion.duration(context, 400);
      intro.forward();
    }
    started = true;
  }

  @override
  void dispose() {
    curve.dispose();
    intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: curve,
    child: widget.child,
    builder: (c, child) => Transform.translate(
      offset: Offset(0, 8 * (1 - curve.value)),
      child: FadeTransition(opacity: curve, child: child),
    ),
  );
}
