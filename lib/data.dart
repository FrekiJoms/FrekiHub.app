import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

part 'data.g.dart';

const maxMoneyMinor = 9000000000000000;
const maxRecordEpoch = 253402300799999;
const maxBackupBytes = 128 * 1024 * 1024;

// Top-level helpers keep the database/FFI handle out of isolate closures.
Future<String> _encodeBackup(Map<String, Object> payload) => Isolate.run(() {
  final source = jsonEncode(payload);
  if (utf8.encode(source).length > maxBackupBytes) {
    throw const FormatException('Backup exceeds the supported 128 MB limit.');
  }
  return source;
});
Future<dynamic> _decodeBackup(String source) => Isolate.run(() {
  if (utf8.encode(source).length > maxBackupBytes) {
    throw const FormatException('Backup exceeds the supported 128 MB limit.');
  }
  return jsonDecode(source);
});
void validateRecordAmount(int amount) {
  if (amount <= 0 || amount > maxMoneyMinor) {
    throw const FormatException(
      'Amount must be positive and within the supported limit.',
    );
  }
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime calendarDate(String s) => DateTime.parse(s);
DateTime calendarOffset(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
String elapsed(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
const currencyDigits = {
  'PHP': 2,
  'USD': 2,
  'EUR': 2,
  'GBP': 2,
  'JPY': 0,
  'KRW': 0,
  'KWD': 3,
};
int parseMoney(String value, String currency) {
  final digits = currencyDigits[currency] ?? 2;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value.trim())) {
    throw const FormatException('Enter a positive amount.');
  }
  final parts = value.trim().split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > digits) {
    throw FormatException('Use at most $digits decimal places.');
  }
  final result =
      BigInt.parse(parts[0]) * BigInt.from(pow(10, digits).toInt()) +
      BigInt.from(digits == 0 ? 0 : int.parse(fraction.padRight(digits, '0')));
  if (result > BigInt.from(9000000000000000)) {
    throw const FormatException('Amount is too large.');
  }
  return result.toInt();
}

String moneySymbol(String currency) =>
    {
      'PHP': '₱',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'JPY': '¥',
      'KRW': '₩',
      'KWD': 'KD ',
    }[currency] ??
    '$currency ';

String money(int minor, String currency) {
  final digits = currencyDigits[currency] ?? 2;
  final scale = pow(10, digits).toInt();
  final absolute = minor.abs();
  final symbol = moneySymbol(currency);
  return '${minor < 0 ? '−' : ''}$symbol${NumberFormat('#,##0').format(absolute ~/ scale)}${digits == 0 ? '' : '.${(absolute % scale).toString().padLeft(digits, '0')}'}';
}

String editableMoney(int minor, String currency) {
  final digits = currencyDigits[currency] ?? 2;
  final scale = pow(10, digits).toInt();
  return '${minor ~/ scale}${digits == 0 ? '' : '.${(minor.abs() % scale).toString().padLeft(digits, '0')}'}';
}

/// Card images live on this device; portable backups keep the design choice but
/// not an absolute path that would be wrong after restoring elsewhere.
bool walletImagePreference(String key) =>
    key.startsWith('wallet:') && key.endsWith(':image');

/// Saved methods can be blank in older imports; those movements belong to cash.
String walletMethodName(String method) {
  final value = method.trim();
  return value.isEmpty ? 'Cash' : value;
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get day => text()();
  TextColumn get kind => text().withDefault(const Constant('OJT'))();
  IntColumn get started => integer()();
  IntColumn get ended => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get day => text()();
  TextColumn get kind => text()();
  IntColumn get amount => integer()();
  TextColumn get currency => text().withDefault(const Constant('PHP'))();
  TextColumn get category => text()();
  TextColumn get method => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get occurrence => text().nullable().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class Rules extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get kind => text()();
  IntColumn get amount => integer()();
  TextColumn get currency => text().withDefault(const Constant('PHP'))();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  TextColumn get basis => text().withDefault(const Constant('fixed'))();
  TextColumn get cadence => text().withDefault(const Constant('monthly'))();
  TextColumn get start => text()();
  TextColumn get finish => text().nullable()();
  TextColumn get category => text()();
  TextColumn get method => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Sessions, Entries, Rules, Preferences])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'frekihub'));
  AppDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX one_running_session ON sessions ((1)) WHERE ended IS NULL',
      );
      await createActivityLogs();
    },
    onUpgrade: (m, from, to) async {
      if (from < 3) await createActivityLogs();
    },
  );
  Future<void> createActivityLogs() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS activity_logs (id TEXT PRIMARY KEY, time INTEGER NOT NULL, action TEXT NOT NULL, title TEXT NOT NULL, location TEXT NOT NULL, details TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_logs_time ON activity_logs(time DESC)',
    );
    const enabled =
        "COALESCE((SELECT value FROM preferences WHERE key = 'activityLogging'), 'false') = 'true'";
    for (final event in [
      'session_start',
      'session_end',
      'transaction',
      'transaction_update',
    ]) {
      final session = event.startsWith('session');
      final table = session ? 'sessions' : 'entries';
      final update = event == 'transaction_update';
      final when = event == 'session_end'
          ? 'AFTER UPDATE OF ended ON sessions WHEN OLD.ended IS NULL AND NEW.ended IS NOT NULL AND $enabled'
          : update
          ? 'AFTER UPDATE ON entries WHEN $enabled AND (OLD.day != NEW.day OR OLD.kind != NEW.kind OR OLD.amount != NEW.amount OR OLD.currency != NEW.currency OR OLD.category != NEW.category OR OLD.method != NEW.method OR OLD.note != NEW.note)'
          : 'AFTER INSERT ON $table WHEN $enabled';
      final time = event == 'session_start'
          ? 'NEW.started'
          : event == 'session_end'
          ? 'NEW.ended'
          : "CAST(strftime('%s','now') AS INTEGER) * 1000";
      const payload =
          "COALESCE((SELECT value FROM preferences WHERE key = 'locationDetails'), '')";
      final valid =
          "CASE WHEN json_valid($payload) THEN json_type($payload, '\$.lat') IN ('real', 'integer') AND json_type($payload, '\$.lng') IN ('real', 'integer') AND json_extract($payload, '\$.lat') BETWEEN -90 AND 90 AND json_extract($payload, '\$.lng') BETWEEN -180 AND 180 AND $time - json_extract($payload, '\$.locationTime') BETWEEN -1000 AND 120000 ELSE 0 END";
      final fresh =
          "COALESCE((SELECT value FROM preferences WHERE key = 'locationEnabled'), 'false') = 'true' AND $time - CAST(COALESCE((SELECT value FROM preferences WHERE key = 'locationSampleTime'), '0') AS INTEGER) BETWEEN -1000 AND 120000 AND ($valid)";
      final place =
          "CASE WHEN $fresh THEN COALESCE((SELECT value FROM preferences WHERE key = 'locationName'), 'Recorded location') ELSE 'Location unavailable' END";
      final position =
          "CASE WHEN $fresh THEN (SELECT value FROM preferences WHERE key = 'locationDetails') ELSE '' END";
      final action = event == 'session_start'
          ? "'clock_in'"
          : event == 'session_end'
          ? "'clock_out'"
          : 'NEW.kind';
      final title = event == 'session_start'
          ? "'Clocked in'"
          : event == 'session_end'
          ? "'Clocked out'"
          : update
          ? "'Updated ' || NEW.kind"
          : "CASE NEW.kind WHEN 'expense' THEN 'Purchased ' || CASE WHEN NEW.note != '' THEN NEW.note ELSE NEW.category END WHEN 'income' THEN 'Received income' ELSE 'Saved money' END";
      final details = session
          ? "json_object('kind', NEW.kind, 'note', NEW.note, 'position', $position)"
          : "json_object('currency', NEW.currency, 'amount', NEW.amount, 'method', NEW.method, 'note', NEW.note, 'position', $position)";
      final id =
          "'$event:' || NEW.id${update ? " || ':' || hex(randomblob(8))" : ''}";
      await customStatement('DROP TRIGGER IF EXISTS log_$event');
      await customStatement(
        "CREATE TRIGGER log_$event $when BEGIN INSERT OR IGNORE INTO activity_logs VALUES ($id, $time, $action, $title, $place, $details); END",
      );
    }
  }

  Stream<List<Map<String, dynamic>>> watchActivityLogs() => customSelect(
    'SELECT * FROM activity_logs ORDER BY time DESC LIMIT 1000',
    readsFrom: {preferences, sessions, entries},
  ).watch().map((rows) => rows.map((r) => r.data).toList());
  Stream<List<Map<String, dynamic>>> watchMapLogs(
    DateTime from,
    DateTime until,
  ) => customSelect(
    'SELECT * FROM activity_logs WHERE time >= ? AND time < ? ORDER BY time ASC, id ASC',
    variables: [
      Variable<int>(from.millisecondsSinceEpoch),
      Variable<int>(until.millisecondsSinceEpoch),
    ],
    readsFrom: {preferences, sessions, entries},
  ).watch().map((rows) => rows.map((r) => r.data).toList());
  Future<void> addActivity(Map<String, dynamic> event) async {
    final existing = await customSelect(
      'SELECT id FROM activity_logs WHERE id = ? UNION ALL SELECT key FROM preferences WHERE key = ?',
      variables: [
        Variable<String>(event['id'] as String),
        Variable<String>('deletedLog:${event['id']}'),
      ],
    ).get();
    if (existing.isNotEmpty) return;
    await customStatement(
      'INSERT OR IGNORE INTO activity_logs VALUES (?, ?, ?, ?, ?, ?)',
      [
        event['id'],
        event['time'],
        event['action'],
        event['title'],
        event['location'] ?? 'Location unavailable',
        jsonEncode(event),
      ],
    );
    await pref('logRevision', DateTime.now().microsecondsSinceEpoch);
    final count = await customSelect(
      'SELECT COUNT(*) AS total FROM activity_logs',
    ).getSingle();
    await pref('activityCount', count.read<int>('total'));
    await pref('lastActivityAction', event['action']);
    await pref('lastActivityTitle', event['title']);
  }

  Future<int> deleteActivityLog(String id) => transaction(() async {
    final removed = await customUpdate(
      'DELETE FROM activity_logs WHERE id = ?',
      variables: [Variable<String>(id)],
    );
    if (removed == 0) return 0;
    // Keep only the identity so a failed native acknowledgement cannot restore it.
    await pref('deletedLog:$id', true);
    final count = await customSelect(
      'SELECT COUNT(*) AS total FROM activity_logs',
    ).getSingle();
    final latest = await customSelect(
      'SELECT action, title FROM activity_logs ORDER BY time DESC, id DESC LIMIT 1',
    ).get();
    await pref('activityCount', count.read<int>('total'));
    await pref(
      'lastActivityAction',
      latest.isEmpty ? '' : latest.first.read<String>('action'),
    );
    await pref(
      'lastActivityTitle',
      latest.isEmpty ? '' : latest.first.read<String>('title'),
    );
    await pref('logRevision', DateTime.now().microsecondsSinceEpoch);
    return removed;
  });

  Stream<AppData> watchAll({
    Duration initialTimeout = const Duration(seconds: 15),
  }) {
    late StreamController<AppData> stream;
    final subscriptions = <StreamSubscription<dynamic>>[];
    List<Session>? sessionRows;
    List<Entry>? entryRows;
    List<Rule>? ruleRows;
    Map<String, String>? prefs;
    Timer? openingDeadline;
    void queryError(Object error, StackTrace stack) {
      openingDeadline?.cancel();
      stream.addError(error, stack);
    }

    void emit() {
      if (sessionRows != null &&
          entryRows != null &&
          ruleRows != null &&
          prefs != null) {
        openingDeadline?.cancel();
        stream.add(AppData(sessionRows!, entryRows!, ruleRows!, prefs!));
      }
    }

    stream = StreamController<AppData>(
      onListen: () {
        openingDeadline = Timer(initialTimeout, () {
          stream.addError(
            TimeoutException(
              'Opening records took too long. Retry to reconnect.',
              initialTimeout,
            ),
          );
        });
        subscriptions.add(
          select(sessions).watch().listen((rows) {
            sessionRows = rows;
            emit();
          }, onError: queryError),
        );
        subscriptions.add(
          select(entries).watch().listen((rows) {
            entryRows = rows;
            emit();
          }, onError: queryError),
        );
        subscriptions.add(
          select(rules).watch().listen((rows) {
            ruleRows = rows;
            emit();
          }, onError: queryError),
        );
        subscriptions.add(
          select(preferences).watch().listen((rows) {
            prefs = {for (final p in rows) p.key: p.value};
            emit();
          }, onError: queryError),
        );
      },
      onCancel: () async {
        openingDeadline?.cancel();
        await Future.wait(subscriptions.map((s) => s.cancel()));
      },
    );
    return stream.stream;
  }

  Future<Map<String, String>> readPreferences() async {
    final prefs = {
      for (final p in await select(preferences).get()) p.key: p.value,
    };
    if ((prefs['automation'] ?? '').contains('"source"')) {
      final count = await customSelect(
        'SELECT COUNT(*) AS total FROM activity_logs',
      ).getSingle();
      final latest = await customSelect(
        'SELECT action, title FROM activity_logs ORDER BY time DESC LIMIT 1',
      ).get();
      prefs['activityCount'] = count.read<int>('total').toString();
      prefs['lastActivityAction'] = latest.isEmpty
          ? ''
          : latest.first.read<String>('action');
      prefs['lastActivityTitle'] = latest.isEmpty
          ? ''
          : latest.first.read<String>('title');
    }
    return prefs;
  }

  Future<AppData> readAll() async {
    final rows = await Future.wait<Object>([
      select(sessions).get(),
      select(entries).get(),
      select(rules).get(),
      readPreferences(),
    ]);
    return AppData(
      rows[0] as List<Session>,
      rows[1] as List<Entry>,
      rows[2] as List<Rule>,
      rows[3] as Map<String, String>,
    );
  }

  Future<void> pref(String key, Object value) => into(preferences)
      .insertOnConflictUpdate(Preference(key: key, value: value.toString()));
  Future<Session> clockIn(String note, {int? at}) => transaction(() async {
    final instant = DateTime.fromMillisecondsSinceEpoch(
      at ?? DateTime.now().millisecondsSinceEpoch,
    );
    final existing = await (select(
      sessions,
    )..where((s) => s.ended.isNull() | s.day.equals(dayKey(instant)))).get();
    if (existing.isNotEmpty) {
      throw StateError(
        'A session already exists for today. Open it to edit or resume your records.',
      );
    }
    final s = Session(
      id: newId(),
      day: dayKey(instant),
      kind: 'OJT',
      started: instant.millisecondsSinceEpoch,
      ended: null,
      note: note,
    );
    await into(sessions).insert(s);
    return s;
  });
  Future<void> clockOut(String id, {int? at}) =>
      (update(
        sessions,
      )..where((s) => s.id.equals(id) & s.ended.isNull())).write(
        SessionsCompanion(
          ended: Value(at ?? DateTime.now().millisecondsSinceEpoch),
        ),
      );
  Future<void> clear() => transaction(() async {
    await customStatement('DELETE FROM activity_logs');
    await delete(entries).go();
    await delete(sessions).go();
    await delete(rules).go();
    await delete(preferences).go();
  });
  Future<void> recordProjection(Projection requested) => transaction(() async {
    final data = await readAll();
    final date = calendarDate(requested.day);
    final candidates = project(
      data,
      date,
      date,
    ).where((p) => p.key == requested.key);
    if (candidates.isEmpty) {
      throw StateError('This planner occurrence no longer exists.');
    }
    final current = candidates.single;
    if (current.status == 'complete') return;
    if (current.error != null) throw StateError(current.error!);
    validateRecordAmount(current.amount);
    await into(entries).insert(
      Entry(
        id: newId(),
        day: current.day,
        kind: current.rule.kind,
        amount: current.amount,
        currency: current.rule.currency,
        category: current.rule.category,
        method: current.rule.method,
        note: current.rule.title,
        occurrence: current.key,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await pref('status:${current.key}', 'planned');
  });
  Future<String> backup() async {
    final payload = await transaction(() async {
      final d = await readAll();
      return {
        'format': 'frekihub',
        'version': 1,
        'sessions': d.sessions.map((s) => s.toJson()).toList(),
        'entries': d.entries.map((e) => e.toJson()).toList(),
        'rules': d.rules.map((r) => r.toJson()).toList(),
        'preferences': {
          for (final entry in d.prefs.entries)
            if (!walletImagePreference(entry.key)) entry.key: entry.value,
        },
        'activityLogs': (await customSelect(
          'SELECT * FROM activity_logs ORDER BY time',
        ).get()).map((r) => r.data).toList(),
      };
    });
    return _encodeBackup(payload);
  }

  Future<void> restore(String source) async {
    final raw = await _decodeBackup(source);
    if (raw is! Map<String, dynamic> ||
        raw['format'] != 'frekihub' ||
        raw['version'] != 1) {
      throw const FormatException('This is not a supported FrekiHub backup.');
    }
    final ss = (raw['sessions'] as List)
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
    final ee = (raw['entries'] as List)
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    final rr = (raw['rules'] as List)
        .map((e) => Rule.fromJson(e as Map<String, dynamic>))
        .toList();
    final pp = Map<String, String>.from(raw['preferences'] as Map);
    final logs = <Map<String, dynamic>>[];
    final logIds = <String>{};
    for (final item in raw['activityLogs'] as List? ?? const []) {
      if (item is! Map ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          !logIds.add(item['id'] as String) ||
          item['time'] is! int ||
          item['time'] < 0 ||
          item['time'] > maxRecordEpoch ||
          item['action'] is! String ||
          (item['action'] as String).isEmpty ||
          item['title'] is! String ||
          item['location'] is! String ||
          item['details'] is! String) {
        throw const FormatException('Invalid activity log in backup.');
      }
      final details = jsonDecode(item['details'] as String);
      if (details is! Map) {
        throw const FormatException('Invalid activity details.');
      }
      final nested = details['position'];
      if (nested != null && nested is! String && nested is! Map) {
        throw const FormatException('Invalid activity position.');
      }
      final position = nested is String && nested.isNotEmpty
          ? jsonDecode(nested)
          : nested is Map
          ? nested
          : details;
      if (position is! Map) {
        throw const FormatException('Invalid activity position.');
      }
      if (position['locationTime'] != null &&
          (position['locationTime'] is! int ||
              position['locationTime'] < 0 ||
              position['locationTime'] > maxRecordEpoch)) {
        throw const FormatException('Invalid location timestamp.');
      }
      if (position['lat'] != null || position['lng'] != null) {
        if (position['lat'] is! num ||
            position['lng'] is! num ||
            !(position['lat'] as num).isFinite ||
            !(position['lng'] as num).isFinite ||
            (position['lat'] as num).abs() > 90 ||
            (position['lng'] as num).abs() > 180) {
          throw const FormatException('Invalid recorded coordinates.');
        }
      }
      logs.add(Map<String, dynamic>.from(item));
    }
    if (pp.containsKey('automation')) {
      final config = jsonDecode(pp['automation']!);
      if (config is! Map ||
          config['rules'] != null && config['rules'] is! List ||
          config['apps'] != null && config['apps'] is! List) {
        throw const FormatException('Invalid automation settings.');
      }
      for (final rule in config['rules'] as List? ?? []) {
        if (rule is! Map ||
            rule['id'] is! String ||
            rule['name'] is! String ||
            rule['lat'] is! num ||
            rule['lng'] is! num ||
            !(rule['lat'] as num).isFinite ||
            !(rule['lng'] as num).isFinite ||
            (rule['lat'] as num).abs() > 90 ||
            (rule['lng'] as num).abs() > 180 ||
            rule['radius'] is! num ||
            (rule['radius'] as num) < 100 ||
            (rule['radius'] as num) > 1000 ||
            !['continue', 'clock_out'].contains(rule['else']) ||
            !['OJT', 'Work', 'Study', 'Personal'].contains(rule['kind'])) {
          throw const FormatException('Invalid location condition.');
        }
      }
      if ((config['apps'] as List? ?? []).any((a) => a is! String)) {
        throw const FormatException('Invalid payment apps.');
      }
    }
    if (pp.containsKey('currency') &&
            !currencyDigits.containsKey(pp['currency']) ||
        pp.containsKey('theme') &&
            !['light', 'dark', 'system'].contains(pp['theme']) ||
        pp.containsKey('dateFormat') &&
            ![
              'EEE, d MMM',
              'dd/MM/yyyy',
              'MM/dd/yyyy',
              'd MMM yyyy',
              'yyyy-MM-dd',
              'relative',
            ].contains(pp['dateFormat'])) {
      throw const FormatException('Invalid settings in backup.');
    }
    for (final key in ['categories', 'methods']) {
      if (pp.containsKey(key)) {
        final values = jsonDecode(pp[key]!);
        if (values is! List ||
            values.isEmpty ||
            values.any((v) => v is! String || v.trim().isEmpty)) {
          throw const FormatException(
            'Invalid category or payment method list.',
          );
        }
      }
    }
    void validateDay(String s) {
      final d = calendarDate(s);
      if (dayKey(d) != s) {
        throw const FormatException('Invalid calendar date in backup.');
      }
    }

    for (final s in ss) {
      validateDay(s.day);
      if (s.started < 0 ||
          s.started > maxRecordEpoch ||
          !['OJT', 'Work', 'Study', 'Personal'].contains(s.kind) ||
          (s.ended != null &&
              (s.ended! < s.started || s.ended! > maxRecordEpoch))) {
        throw const FormatException('Invalid session.');
      }
    }
    if (ss.where((s) => s.ended == null).length > 1) {
      throw const FormatException('Backup contains multiple running sessions.');
    }
    for (final e in ee) {
      validateDay(e.day);
      if (e.amount < 0 ||
          e.amount > 9000000000000000 ||
          !currencyDigits.containsKey(e.currency) ||
          !['income', 'expense', 'savings'].contains(e.kind)) {
        throw const FormatException('Invalid transaction.');
      }
    }
    for (final r in rr) {
      validateDay(r.start);
      if (r.finish != null) {
        validateDay(r.finish!);
      }
      if (r.amount < 0 ||
          BigInt.from(r.amount) * BigInt.from(r.quantity) >
              BigInt.from(9000000000000000) ||
          (r.basis != 'fixed' && r.amount > 10000) ||
          r.quantity < 1 ||
          r.quantity > 100000 ||
          !currencyDigits.containsKey(r.currency) ||
          !['income', 'expense', 'savings'].contains(r.kind) ||
          (r.finish != null && r.finish!.compareTo(r.start) < 0) ||
          !['once', 'daily', 'weekly', 'monthly'].contains(r.cadence) ||
          !['fixed', 'income', 'expenses', 'net'].contains(r.basis)) {
        throw const FormatException('Invalid planner rule.');
      }
    }
    await transaction(() async {
      await clear();
      for (final s in ss) {
        await into(sessions).insert(s);
      }
      for (final e in ee) {
        await into(entries).insert(e);
      }
      for (final r in rr) {
        await into(rules).insert(r);
      }
      for (final p in pp.entries) {
        await pref(p.key, p.value);
      }
      for (final item in logs) {
        await customStatement(
          'INSERT INTO activity_logs VALUES (?, ?, ?, ?, ?, ?)',
          [
            item['id'],
            item['time'],
            item['action'],
            item['title'],
            item['location'],
            item['details'],
          ],
        );
      }
    });
  }
}

class AppData {
  final List<Session> sessions;
  final List<Entry> entries;
  final List<Rule> rules;
  final Map<String, String> prefs;
  AppData(this.sessions, this.entries, this.rules, this.prefs);
  String get currency => prefs['currency'] ?? 'PHP';
  List<String> get categories => list('categories', [
    'Food',
    'Transport',
    'Home',
    'Personal',
    'Work',
    'Salary',
    'Savings',
    'Other',
  ]);
  List<String> get methods =>
      list('methods', ['Cash', 'GCash', 'Maya', 'Bank', 'Card']);

  /// Wallets explicitly removed by the user so historical entries do not
  /// resurrect them on Finance unless re-added.
  Set<String> get hiddenWallets {
    try {
      final raw = jsonDecode(prefs['hiddenWallets']!) as List;
      return raw.map((e) => e.toString().trim().toLowerCase()).toSet();
    } catch (_) {
      return const {};
    }
  }

  /// Wallets are the saved payment methods plus any active method referenced by
  /// a transaction, merged case-insensitively and excluding removed/messaging ones.
  List<String> get walletMethods {
    final hidden = hiddenWallets;
    final byLower = <String, String>{};
    for (final m in methods) {
      final trimmed = m.trim();
      if (trimmed.isEmpty || _isMessagingMethod(trimmed)) continue;
      byLower.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }
    for (final e in entries.where((e) => e.currency == currency)) {
      final name = walletMethodName(e.method);
      final lower = name.toLowerCase();
      if (_isMessagingMethod(name) || hidden.contains(lower)) continue;
      byLower.putIfAbsent(lower, () => name);
    }
    return byLower.values.toList();
  }

  String _canonicalWalletName(String method) {
    final name = walletMethodName(method);
    final lower = name.toLowerCase();
    for (final canonical in walletMethods) {
      if (canonical.toLowerCase() == lower) return canonical;
    }
    return name;
  }

  static bool _isMessagingMethod(String name) {
    final lower = name.trim().toLowerCase();
    return lower == 'messaging' || lower == 'messages';
  }

  /// One pass over the current currency's ledger, keyed by canonical payment method.
  Map<String, int> get walletBalances {
    final hidden = hiddenWallets;
    final list = walletMethods;
    final byLower = <String, String>{
      for (final name in list) name.toLowerCase(): name,
    };
    final result = <String, int>{for (final name in list) name: 0};
    for (final e in entries.where((e) => e.currency == currency)) {
      final raw = walletMethodName(e.method);
      final lower = raw.toLowerCase();
      if (_isMessagingMethod(raw) || hidden.contains(lower)) {
        continue;
      }
      final name = byLower[lower] ?? raw;
      result.update(
        name,
        (value) => value + (e.kind == 'income' ? e.amount : -e.amount),
        ifAbsent: () => e.kind == 'income' ? e.amount : -e.amount,
      );
    }
    return result;
  }

  int walletBalance(String method) => walletBalances[_canonicalWalletName(method)] ?? 0;

  List<Entry> walletEntries(String method) {
    final target = method.trim().toLowerCase();
    return entries
        .where(
          (e) =>
              e.currency == currency &&
              walletMethodName(e.method).toLowerCase() == target,
        )
        .toList();
  }

  /// Ledger rows in the display currency, optionally narrowed to one month and
  /// one payment method. Finance uses this so every summary, chart and timeline
  /// changes together when a wallet is selected.
  List<Entry> scopedEntries({String? wallet, String? month}) {
    final target = wallet?.trim().toLowerCase();
    return entries
        .where(
          (e) =>
              e.currency == currency &&
              (month == null || e.day.startsWith(month)) &&
              (target == null ||
                  walletMethodName(e.method).toLowerCase() == target),
        )
        .toList();
  }

  /// Lifetime savings contributions per wallet for the goal breakdown.
  Map<String, int> get savingsByWallet {
    final result = <String, int>{};
    for (final e in entries.where(
      (e) => e.currency == currency && e.kind == 'savings',
    )) {
      final name = walletMethodName(e.method);
      result.update(name, (value) => value + e.amount, ifAbsent: () => e.amount);
    }
    return result;
  }

  /// Saved order first, then new or previously unlisted methods by importance.
  List<String> orderedWalletNames(Iterable<String> stored) {
    final balances = walletBalances;
    final remaining = <String, int>{...balances};
    final result = <String>[];
    for (final name in stored) {
      if (remaining.remove(name) != null) result.add(name);
    }
    final rest = remaining.keys.toList()
      ..sort((a, b) {
        final byBalance = (remaining[b] ?? 0).abs().compareTo(
          (remaining[a] ?? 0).abs(),
        );
        return byBalance != 0 ? byBalance : a.compareTo(b);
      });
    return [...result, ...rest];
  }

  List<String> list(String key, List<String> fallback) {
    try {
      final values = List<String>.from(jsonDecode(prefs[key]!) as List);
      return values.isEmpty ? fallback : values;
    } catch (_) {
      return fallback;
    }
  }

  Session? get running {
    for (final s in sessions) {
      if (s.ended == null) {
        return s;
      }
    }
    return null;
  }

  int get balance => total('income') - total('expense') - total('savings');

  int total(String kind, {String? month}) => entries
      .where(
        (e) =>
            e.currency == currency &&
            e.kind == kind &&
            (month == null || e.day.startsWith(month)),
      )
      .fold(0, (sum, e) => sum + e.amount);
}

class Projection {
  final Rule rule;
  final String day;
  final int amount;
  final String status;
  final String? error;
  Projection(this.rule, this.day, this.amount, this.status, {this.error});
  String get key => '${rule.id}:$day';
}

List<Projection> project(AppData data, DateTime from, DateTime until) {
  final result = <Projection>[];
  final recordedOccurrences = data.entries.map((e) => e.occurrence).toSet();
  final monthlyTotals = <String, (BigInt, BigInt)>{};
  for (final r in data.rules.where((r) => r.currency == data.currency)) {
    final start = calendarDate(r.start);
    for (
      var d = DateTime(from.year, from.month, from.day);
      !d.isAfter(until);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      if (d.isBefore(start) ||
          (r.finish != null && d.isAfter(calendarDate(r.finish!)))) {
        continue;
      }
      final days = DateTime.utc(
        d.year,
        d.month,
        d.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      final match = switch (r.cadence) {
        'once' => days == 0,
        'daily' => true,
        'weekly' => days % 7 == 0,
        _ => d.day == min(start.day, DateTime(d.year, d.month + 1, 0).day),
      };
      if (!match) {
        continue;
      }
      final month = dayKey(d).substring(0, 7);
      final totals = monthlyTotals.putIfAbsent(month, () {
        var income = BigInt.zero, expenses = BigInt.zero;
        for (final entry in data.entries.where(
          (e) => e.currency == data.currency && e.day.startsWith(month),
        )) {
          if (entry.kind == 'income') income += BigInt.from(entry.amount);
          if (entry.kind == 'expense') expenses += BigInt.from(entry.amount);
        }
        return (income, expenses);
      });
      final income = totals.$1;
      final expenses = totals.$2;
      final base = switch (r.basis) {
        'income' => income,
        'expenses' => expenses,
        'net' => income > expenses ? income - expenses : BigInt.zero,
        _ => BigInt.zero,
      };
      final calculated = r.basis == 'fixed'
          ? BigInt.from(r.amount) * BigInt.from(r.quantity)
          : ((base * BigInt.from(r.amount) * BigInt.from(r.quantity) +
                    BigInt.from(5000)) ~/
                BigInt.from(10000));
      final invalid =
          calculated < BigInt.zero || calculated > BigInt.from(maxMoneyMinor);
      final amount = invalid ? 0 : calculated.toInt();
      final key = '${r.id}:${dayKey(d)}';
      final recorded = recordedOccurrences.contains(key);
      result.add(
        Projection(
          r,
          dayKey(d),
          amount,
          recorded
              ? 'complete'
              : ['skipped', 'cancelled'].contains(data.prefs['status:$key'])
              ? data.prefs['status:$key']!
              : invalid
              ? 'invalid'
              : 'planned',
          error: invalid
              ? 'Projected amount exceeds the supported limit. Edit this planner rule.'
              : null,
        ),
      );
    }
  }
  result.sort((a, b) {
    final date = a.day.compareTo(b.day);
    return date == 0 ? a.rule.position.compareTo(b.rule.position) : date;
  });
  return result;
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final dataProvider = StreamProvider<AppData>(
  (ref) => ref.watch(databaseProvider).watchAll(),
);
