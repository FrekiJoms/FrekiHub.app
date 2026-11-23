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
            _MarkdownNotes(widget.info.notes),
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

/// Renders release-note Markdown without external package dependencies.
class _MarkdownNotes extends StatelessWidget {
  final String source;
  const _MarkdownNotes(this.source);

  static final _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _hrRe = RegExp(r'^\s*(?:[-*_]\s*){3,}$');
  static final _ulRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final _olRe = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');
  static final _taskRe = RegExp(r'^\[( |x|X)\]\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base =
        theme.textTheme.bodyMedium ??
        TextStyle(fontSize: 14, height: 1.45, color: colors.onSurface);
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++;
        blocks.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              codeLines.join('\n'),
              style: TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 12.5,
                height: 1.4,
                color: colors.onSurface,
              ),
            ),
          ),
        );
        continue;
      }

      if (_hrRe.hasMatch(trimmed)) {
        blocks.add(
          Divider(height: 12, thickness: 1, color: colors.outlineVariant),
        );
        i++;
        continue;
      }

      final heading = _headingRe.firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final text = heading.group(2)!.replaceFirst(RegExp(r'\s+#+\s*$'), '');
        final style = base.copyWith(
          fontSize: level == 1
              ? 18
              : level == 2
              ? 16
              : 14.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        );
        blocks.add(
          Semantics(
            header: true,
            child: Text.rich(_inlineSpan(text, style, colors)),
          ),
        );
        i++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.outlineVariant, width: 3),
              ),
            ),
            child: Text.rich(
              _inlineSpan(
                quoteLines.join(' '),
                base.copyWith(color: colors.onSurfaceVariant),
                colors,
              ),
            ),
          ),
        );
        continue;
      }

      final ul = _ulRe.firstMatch(line);
      final ol = ul == null ? _olRe.firstMatch(line) : null;
      if (ul != null || ol != null) {
        final items = <Widget>[];
        while (i < lines.length) {
          final current = lines[i];
          final mUl = _ulRe.firstMatch(current);
          final mOl = mUl == null ? _olRe.firstMatch(current) : null;
          if (mUl == null && mOl == null) break;
          final indent = ((mUl?.group(1) ?? mOl!.group(1))!).length;
          final nested = indent >= 2;
          var body = (mUl?.group(2) ?? mOl!.group(3))!.trim();
          final task = _taskRe.firstMatch(body);
          final String marker;
          if (task != null) {
            final checked = task.group(1)!.toLowerCase() == 'x';
            marker = checked ? '☑' : '☐';
            body = task.group(2)!.trim();
          } else if (mOl != null) {
            marker = '${mOl.group(2)!}.';
          } else {
            marker = nested ? '◦' : '•';
          }
          items.add(
            Padding(
              padding: EdgeInsets.only(left: nested ? 16 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: mOl != null ? 24 : 16,
                    child: Text(
                      marker,
                      style: base.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Text.rich(_inlineSpan(body, base, colors))),
                ],
              ),
            ),
          );
          i++;
        }
        blocks.add(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < items.length; j++) ...[
                if (j > 0) const SizedBox(height: 6),
                items[j],
              ],
            ],
          ),
        );
        continue;
      }

      final paraLines = <String>[];
      while (i < lines.length) {
        final cur = lines[i];
        final curTrim = cur.trim();
        if (curTrim.isEmpty ||
            curTrim.startsWith('```') ||
            curTrim.startsWith('>') ||
            _hrRe.hasMatch(curTrim) ||
            _headingRe.hasMatch(curTrim) ||
            _ulRe.hasMatch(cur) ||
            _olRe.hasMatch(cur)) {
          break;
        }
        paraLines.add(curTrim);
        i++;
      }
      blocks.add(Text.rich(_inlineSpan(paraLines.join(' '), base, colors)));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var j = 0; j < blocks.length; j++) ...[
          if (j > 0) const SizedBox(height: 10),
          blocks[j],
        ],
      ],
    );
  }

  static InlineSpan _inlineSpan(
    String text,
    TextStyle style,
    ColorScheme colors,
  ) => TextSpan(style: style, children: _parseInline(text, style, colors));

  static bool _isWordChar(String s, int index) {
    if (index < 0 || index >= s.length) return false;
    final code = s.codeUnitAt(index);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
  }

  static List<InlineSpan> _parseInline(
    String text,
    TextStyle style,
    ColorScheme colors,
  ) {
    final spans = <InlineSpan>[];
    final buf = StringBuffer();

    void flushText() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      final ch = text[i];

      if (ch == r'\' && i + 1 < text.length) {
        buf.write(text[i + 1]);
        i += 2;
        continue;
      }

      if (ch == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          flushText();
          spans.add(
            TextSpan(
              text: text.substring(i + 1, end),
              style: style.copyWith(
                fontFamily: 'Geist Mono',
                fontSize: (style.fontSize ?? 14) * .92,
                backgroundColor: colors.surfaceContainerHigh,
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }

      if (ch == '[') {
        final closeBracket = text.indexOf(']', i + 1);
        if (closeBracket != -1 &&
            closeBracket + 1 < text.length &&
            text[closeBracket + 1] == '(') {
          final closeParen = text.indexOf(')', closeBracket + 2);
          if (closeParen != -1) {
            final label = text.substring(i + 1, closeBracket);
            final target = text.substring(closeBracket + 2, closeParen).trim();
            if (target.startsWith('https://') ||
                target.startsWith('http://') ||
                target.startsWith('#')) {
              flushText();
              spans.add(
                TextSpan(
                  style: style.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: colors.onSurfaceVariant,
                  ),
                  children: _parseInline(label, style, colors),
                ),
              );
              i = closeParen + 1;
              continue;
            }
          }
        }
      }

      if (text.startsWith('***', i) || text.startsWith('___', i)) {
        final delim = text.substring(i, i + 3);
        final end = text.indexOf(delim, i + 3);
        if (end != -1) {
          flushText();
          final innerStyle = style.copyWith(
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
          );
          spans.add(
            TextSpan(
              style: innerStyle,
              children: _parseInline(
                text.substring(i + 3, end),
                innerStyle,
                colors,
              ),
            ),
          );
          i = end + 3;
          continue;
        }
      }

      if (text.startsWith('**', i) || text.startsWith('__', i)) {
        final delim = text.substring(i, i + 2);
        final end = text.indexOf(delim, i + 2);
        if (end != -1) {
          flushText();
          final innerStyle = style.copyWith(fontWeight: FontWeight.w600);
          spans.add(
            TextSpan(
              style: innerStyle,
              children: _parseInline(
                text.substring(i + 2, end),
                innerStyle,
                colors,
              ),
            ),
          );
          i = end + 2;
          continue;
        }
      }

      if (text.startsWith('~~', i)) {
        final end = text.indexOf('~~', i + 2);
        if (end != -1) {
          flushText();
          final innerStyle = style.copyWith(
            decoration: TextDecoration.lineThrough,
          );
          spans.add(
            TextSpan(
              style: innerStyle,
              children: _parseInline(
                text.substring(i + 2, end),
                innerStyle,
                colors,
              ),
            ),
          );
          i = end + 2;
          continue;
        }
      }

      if (ch == '*' || (ch == '_' && !_isWordChar(text, i - 1))) {
        final end = text.indexOf(ch, i + 1);
        if (end != -1 &&
            end > i + 1 &&
            text[i + 1] != ' ' &&
            text[end - 1] != ' ' &&
            (ch != '_' || !_isWordChar(text, end + 1))) {
          flushText();
          final innerStyle = style.copyWith(fontStyle: FontStyle.italic);
          spans.add(
            TextSpan(
              style: innerStyle,
              children: _parseInline(
                text.substring(i + 1, end),
                innerStyle,
                colors,
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }

      buf.write(ch);
      i++;
    }

    flushText();
    return spans;
  }
}
