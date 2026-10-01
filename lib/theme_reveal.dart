import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'design.dart';

abstract final class ThemeReveal {
  static final key = GlobalKey();
  static bool active = false;
  static Future<void> change(
    BuildContext context,
    Offset origin,
    Future<void> Function() change,
  ) async {
    if (active || MediaQuery.disableAnimationsOf(context)) {
      await change();
      return;
    }
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) {
      await change();
      return;
    }
    final overlay = Overlay.of(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    active = true;
    ui.Image? image;
    OverlayEntry? entry;
    final start = ValueNotifier<bool>(false);
    try {
      image = await boundary.toImage(pixelRatio: pixelRatio);
      final captured = image;
      entry = OverlayEntry(
        builder: (c) => Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: start,
              builder: (c, running, _) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: running ? 1 : 0),
                duration: Motion.duration(c, 400),
                curve: Motion.curve,
                builder: (c, t, _) => ClipPath(
                  clipper: _RevealClip(origin, t),
                  child: RawImage(image: captured, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      await change();
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      start.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } finally {
      entry?.remove();
      await WidgetsBinding.instance.endOfFrame;
      start.dispose();
      image?.dispose();
      active = false;
    }
  }
}

class _RevealClip extends CustomClipper<Path> {
  final Offset origin;
  final double progress;
  _RevealClip(this.origin, this.progress);
  @override
  Path getClip(Size size) {
    final radius =
        math.sqrt(size.width * size.width + size.height * size.height) *
        progress;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
  }

  @override
  bool shouldReclip(_RevealClip old) =>
      old.progress != progress || old.origin != origin;
}
