import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;

import 'data.dart';

abstract final class NativeSession {
  static const channel = MethodChannel('frekihub/session');
  static Map<String, dynamic> _payload(Session s) => {
    'id': s.id,
    'started': s.started,
    'day': s.day,
    'kind': s.kind,
    'note': s.note,
  };

  /// Record running state independently of optional notification access.
  static Future<bool> cache(Session s) async {
    try {
      return await channel.invokeMethod<bool>('cacheSession', _payload(s)) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> start(Session s) async {
    try {
      return await channel.invokeMethod<bool>('start', _payload(s)) ?? false;
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

  /// Legacy actions omit the note; overlay drafts apply only to a running record.
  static Future<void> applyPending(
    AppDatabase db,
    Map<String, dynamic> pending,
  ) => db.transaction(() async {
    final id = pending['id'] as String;
    if (pending['note'] is String) {
      await (db.update(db.sessions)
            ..where((s) => s.id.equals(id) & s.ended.isNull()))
          .write(SessionsCompanion(note: Value(pending['note'] as String)));
    }
    await db.clockOut(id, at: pending['ended'] as int);
  });
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
