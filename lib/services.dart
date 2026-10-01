import 'package:flutter/services.dart';
import 'package:soundpool/soundpool.dart';

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
  static final pool = Soundpool.fromOptions(
    options: const SoundpoolOptions(streamType: StreamType.notification),
  );
  static final Map<String, Future<int>> loaded = {};
  static Future<void> play(bool enabled, String name) async {
    if (!enabled) {
      return;
    }
    try {
      final id = await loaded.putIfAbsent(
        name,
        () async => pool.load(await rootBundle.load('assets/sounds/$name.wav')),
      );
      await pool.play(id);
    } catch (_) {
      /* Feedback must never interrupt a saved record. */
    }
  }
}
