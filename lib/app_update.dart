import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'design.dart';
import 'services.dart';

const _buildUpdateUrl = String.fromEnvironment('UPDATE_URL');

class AppVersionInfo {
  final String versionName;
  final int versionCode;
  const AppVersionInfo({required this.versionName, required this.versionCode});

  String get label => '$versionName ($versionCode)';
}

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;
  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes = '',
  });

  static bool _isHttpsUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static AppUpdateInfo? parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['apkUrl'] is String && map['versionCode'] is num) {
      final code = (map['versionCode'] as num).toInt();
      final url = (map['apkUrl'] as String).trim();
      if (code <= 0 || !_isHttpsUrl(url)) return null;
      return AppUpdateInfo(
        versionCode: code,
        versionName: (map['versionName'] as String? ?? '').trim().isEmpty
            ? '$code'
            : (map['versionName'] as String).trim(),
        apkUrl: url,
        notes: (map['notes'] as String? ?? '').trim(),
      );
    }
    if (map['tag_name'] is String && map['assets'] is List) {
      final tag = (map['tag_name'] as String).trim();
      final body = (map['body'] as String? ?? '').trim();
      final plusMatch = RegExp(r'\+(\d+)$').firstMatch(tag);
      final bodyCodeMatch = RegExp(
        r'(?:versionCode|build)\s*[:=]\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(body);
      final intTagMatch = RegExp(r'^v?(\d+)$').firstMatch(tag);
      final code = plusMatch != null
          ? int.tryParse(plusMatch.group(1)!)
          : bodyCodeMatch != null
          ? int.tryParse(bodyCodeMatch.group(1)!)
          : intTagMatch != null
          ? int.tryParse(intTagMatch.group(1)!)
          : null;
      if (code == null || code <= 0) return null;
      final apks = (map['assets'] as List)
          .whereType<Map>()
          .map((a) => Map<String, dynamic>.from(a))
          .where((a) {
            final name = (a['name'] as String? ?? '').toLowerCase();
            final url = (a['browser_download_url'] as String? ?? '').trim();
            return name.endsWith('.apk') && _isHttpsUrl(url);
          })
          .toList();
      if (apks.isEmpty) return null;
      final preferred = apks.firstWhere((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        return kDebugMode ? name.contains('debug') : !name.contains('debug');
      }, orElse: () => apks.first);
      final cleanName = tag
          .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\+\d+$'), '')
          .trim();
      final title = (map['name'] as String? ?? '').trim();
      final notes = body.isNotEmpty ? body : title;
      return AppUpdateInfo(
        versionCode: code,
        versionName: cleanName.isEmpty ? '$code' : cleanName,
        apkUrl: (preferred['browser_download_url'] as String).trim(),
        notes: notes,
      );
    }
    return null;
  }
}

abstract final class AppUpdater {
  static final ValueNotifier<({double? progress, int received, int total})?>
  _progress = ValueNotifier(null);
  static final ValueNotifier<({String status, String? message})?> _status =
      ValueNotifier(null);
  static bool _handlerRegistered = false;

  static void _ensureHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    NativeSession.channel.setMethodCallHandler((call) async {
      if (call.method == 'updateProgress' && call.arguments is Map) {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final p = args['progress'];
        _progress.value = (
          progress: p is num ? p.toDouble().clamp(0.0, 1.0) : null,
          received: (args['received'] as num?)?.toInt() ?? 0,
          total: (args['total'] as num?)?.toInt() ?? -1,
        );
      } else if (call.method == 'updateStatus' && call.arguments is Map) {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _status.value = (
          status: args['status'] as String? ?? 'failed',
          message: args['message'] as String?,
        );
      }
    });
  }

  /// Fixed update endpoint compiled into the app; not user-editable.
  static String get configuredUrl => _buildUpdateUrl.trim();

  static Uri? resolveUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(trimmed)) {
      return Uri.parse('https://api.github.com/repos/$trimmed/releases/latest');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.scheme != 'https') return null;
    if (parsed.host == 'github.com' &&
        parsed.pathSegments.length >= 2 &&
        !parsed.pathSegments.contains('releases') &&
        !parsed.pathSegments.contains('raw')) {
      return Uri.parse(
        'https://api.github.com/repos/${parsed.pathSegments[0]}/${parsed.pathSegments[1]}/releases/latest',
      );
    }
    return parsed;
  }

  static Future<AppVersionInfo?> currentVersion() async {
    try {
      final raw = await NativeSession.channel.invokeMapMethod<String, dynamic>(
        'appVersion',
      );
      if (raw == null) return null;
      final code = (raw['versionCode'] as num?)?.toInt();
      if (code == null) return null;
      return AppVersionInfo(
        versionName: (raw['versionName'] as String? ?? '1.0.0').trim(),
        versionCode: code,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<AppUpdateInfo?> check(
    String rawSource, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = resolveUri(rawSource);
    if (uri == null) {
      throw const FormatException(
        'Enter an HTTPS manifest URL or GitHub owner/repo.',
      );
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FrekiAppUpdater');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Server returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      final parsed = AppUpdateInfo.parse(decoded);
      if (parsed == null) {
        throw const FormatException('Update manifest has no compatible APK.');
      }
      return parsed;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> showUpdateSheet(
    BuildContext context,
    AppUpdateInfo info, {
    required AppVersionInfo current,
  }) {
    _ensureHandler();
    return panel<void>(context, _UpdateSheet(info: info, current: current));
  }
}

class _UpdateSheet extends StatefulWidget {
  final AppUpdateInfo info;
  final AppVersionInfo current;
  const _UpdateSheet({required this.info, required this.current});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _awaitingInstallGrant = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdater._status.addListener(_onStatus);
    AppUpdater._progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppUpdater._status.removeListener(_onStatus);
    AppUpdater._progress.removeListener(_onProgress);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingInstallGrant) {
      _awaitingInstallGrant = false;
      unawaited(_resumeAfterPermissionReturn());
    }
  }

  Future<void> _resumeAfterPermissionReturn() async {
    try {
      final status = await NativeSession.channel
          .invokeMapMethod<String, dynamic>('permissionStatus');
      if (mounted && status?['installPackagesPermission'] == true && !_busy) {
        await _startInstall();
      }
    } catch (_) {}
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  void _onStatus() {
    final s = AppUpdater._status.value;
    if (s == null || !mounted) return;
    if (s.status == 'committing' || s.status == 'confirming') {
      setState(() => _statusText = 'Opening Android installer…');
    } else if (s.status == 'installed') {
      setState(() {
        _busy = false;
        _statusText = 'Update installed';
      });
      toast(context, 'Update installed');
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        Navigator.pop(context);
      }
    } else if (s.status == 'cancelled') {
      setState(() {
        _busy = false;
        _statusText = null;
      });
    } else if (s.status == 'failed') {
      setState(() {
        _busy = false;
        _statusText = null;
      });
      toast(context, s.message ?? 'Could not install update.', error: true);
    }
  }

  Future<void> _startInstall() async {
    if (_busy) return;
    try {
      final allowed = await PermissionHints.request<bool>(
        context,
        'installPackagesPermission',
      );
      if (!mounted) return;
      if (allowed != true) {
        final status = await NativeSession.channel
            .invokeMapMethod<String, dynamic>('permissionStatus');
        if (status?['installPackagesPermission'] != true) {
          // Only resume installation automatically if Settings was opened
          // rather than declined via "Not now" or Back.
          _awaitingInstallGrant = allowed == false;
          return;
        }
      }
      AppUpdater._progress.value = null;
      AppUpdater._status.value = null;
      setState(() {
        _busy = true;
        _statusText = 'Downloading update…';
      });
      await NativeSession.channel.invokeMethod('installUpdate', {
        'url': widget.info.apkUrl,
        'versionCode': widget.info.versionCode,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = null;
      });
      toast(
        context,
        e is PlatformException
            ? (e.message ?? 'Could not start update.')
            : 'Could not start update.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppUpdater._progress.value;
    final pct = p?.progress != null ? '${(p!.progress! * 100).round()}%' : null;
    return PanelContent(
      header: PanelHeading(
        title: 'Update available',
        leading: Chrome(
          padding: const EdgeInsets.all(10),
          child: const Icon(LucideIcons.download, size: 20),
        ),
      ),
      footer: PanelActions(
        children: [
          AppButton(
            label: _busy ? (pct ?? 'Updating…') : 'Update',
            busy: _busy,
            onPressed: _busy ? null : _startInstall,
          ),
          AppButton(
            label: 'Later',
            secondary: true,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Version ${widget.info.versionName} (${widget.info.versionCode})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Installed: ${widget.current.label}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.info.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(widget.info.notes),
          ],
          if (_busy) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: p?.progress, minHeight: 6),
            ),
            if (_statusText != null) ...[
              const SizedBox(height: 8),
              Text(
                pct == null ? _statusText! : '$_statusText ($pct)',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
