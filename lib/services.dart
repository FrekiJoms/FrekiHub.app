import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;

import 'data.dart';
import 'map_records.dart';

/// Foreground record capture. Native replay keeps its original event sample.
abstract final class RecordLocation {
  static Future<T> commit<T>(
    AppDatabase db,
    Future<T> Function() save, {
    required Future<bool> Function() permission,
  }) async {
    final prefs = await db.readPreferences();
    if (prefs['activityLogging'] != 'true' ||
        prefs['locationEnabled'] != 'true') {
      return db.transaction(save);
    }
    MapUserLocation? fix;
    if (prefs['activityLogging'] == 'true' &&
        prefs['locationEnabled'] == 'true') {
      try {
        if (await permission()) {
          final raw = await NativeSession.channel
              .invokeMethod<String>('mapCurrentLocation')
              .timeout(const Duration(seconds: 25));
          fix = MapUserLocation.parse(raw, DateTime.now());
        }
      } on PlatformException {
        // Location is optional: a failed fix must not discard the record.
      } on MissingPluginException {
        // Unsupported previews still save records.
      } on TimeoutException {
        // A bounded request never blocks saving indefinitely.
      } catch (_) {
        // Any permission or location lookup issue must not discard the record.
      }
    }
    return db.transaction(() async {
      // Never borrow a previous action's coordinates when this request fails.
      await db.pref(
        'locationName',
        fix == null ? 'Location unavailable' : 'Recorded location',
      );
      await db.pref('locationSampleTime', fix?.sampled ?? 0);
      await db.pref(
        'locationDetails',
        fix == null
            ? ''
            : jsonEncode({
                'lat': fix.lat,
                'lng': fix.lng,
                'accuracy': fix.accuracy,
                'locationTime': fix.sampled,
              }),
      );
      return save();
    });
  }
}

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
    final ended = pending['ended'] as int;
    final record = await (db.select(
      db.sessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (record == null || record.ended != null) return;
    if (ended < record.started || ended > maxRecordEpoch) {
      throw const FormatException('Invalid pending session end.');
    }
    final fix = MapUserLocation.parse(
      pending['position'],
      DateTime.fromMillisecondsSinceEpoch(ended),
    );
    final prefs = fix == null ? null : await db.readPreferences();
    if (fix != null) {
      final position = MapRecord.decode(pending['position']);
      await db.pref(
        'locationName',
        position['location'] ?? 'Recorded location',
      );
      await db.pref('locationSampleTime', fix.sampled);
      await db.pref('locationDetails', jsonEncode(position));
    }
    if (pending['note'] is String) {
      await (db.update(db.sessions)
            ..where((s) => s.id.equals(id) & s.ended.isNull()))
          .write(SessionsCompanion(note: Value(pending['note'] as String)));
    }
    await db.clockOut(id, at: ended);
    // Use the event's own sample for its trigger without regressing the live cache.
    if (prefs != null) {
      for (final key in [
        'locationName',
        'locationSampleTime',
        'locationDetails',
      ]) {
        if (prefs.containsKey(key)) {
          await db.pref(key, prefs[key]!);
        } else {
          await (db.delete(
            db.preferences,
          )..where((p) => p.key.equals(key))).go();
        }
      }
    }
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
