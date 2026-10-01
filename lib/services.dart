import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'data.dart';

abstract final class NativeSession {
  static const channel = MethodChannel('frekihub/session');
  static Future<bool> start(Session s, {int todaySeconds = 0}) async {
    try {
      return await channel.invokeMethod<bool>('start', {
            'id': s.id,
            'started': s.started,
            'day': s.day,
            'todaySeconds': todaySeconds,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      /* Database remains the source of truth. */
    } on MissingPluginException {
      /* Unsupported desktop preview. */
    }
  }

  static Future<Map<String, dynamic>?> pending() async {
    try {
      return await channel.invokeMapMethod<String, dynamic>('pending');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> acknowledge() =>
      channel.invokeMethod<void>('acknowledge');
}

abstract final class FeedbackSound {
  static Future<void> play(bool enabled, String name) async {
    if (!enabled) {
      return;
    }
    try {
      await NativeSession.channel.invokeMethod<void>('sound', name);
    } catch (_) {
      /* Feedback must never interrupt a saved record. */
    }
  }
}

VoidCallback? withFeedback(VoidCallback? action) => action == null
    ? null
    : () {
        ActionFeedback.tap();
        action();
      };

abstract final class ActionFeedback {
  static bool soundEnabled = false;
  static final _clock = Stopwatch()..start();
  static int _lastTap = -150;
  static void tap({bool transition = false}) {
    if (_clock.elapsedMilliseconds - _lastTap < 100) return;
    _lastTap = _clock.elapsedMilliseconds;
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      FeedbackSound.play(soundEnabled, transition ? 'transition' : 'click'),
    );
  }
}

class FeedbackNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) ActionFeedback.tap(transition: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) ActionFeedback.tap(transition: true);
  }
}
