import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

part 'data.g.dart';

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime calendarDate(String s) => DateTime.parse(s);
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

String money(int minor, String currency) {
  final digits = currencyDigits[currency] ?? 2;
  final scale = pow(10, digits).toInt();
  final absolute = minor.abs();
  final symbol =
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
  return '${minor < 0 ? '−' : ''}$symbol${NumberFormat('#,##0').format(absolute ~/ scale)}${digits == 0 ? '' : '.${(absolute % scale).toString().padLeft(digits, '0')}'}';
}

String editableMoney(int minor, String currency) {
  final digits = currencyDigits[currency] ?? 2;
  final scale = pow(10, digits).toInt();
  return '${minor ~/ scale}${digits == 0 ? '' : '.${(minor.abs() % scale).toString().padLeft(digits, '0')}'}';
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
  int get schemaVersion => 2;
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
      if (from < 2) await createActivityLogs();
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
    const place =
        "CASE WHEN CAST(strftime('%s','now') AS INTEGER) * 1000 - CAST(COALESCE((SELECT value FROM preferences WHERE key = 'locationSampleTime'), '0') AS INTEGER) BETWEEN -1000 AND 120000 THEN COALESCE((SELECT value FROM preferences WHERE key = 'locationName'), 'Location unavailable') ELSE 'Location unavailable' END";
    const position =
        "COALESCE((SELECT value FROM preferences WHERE key = 'locationDetails'), '')";
    for (final event in ['session_start', 'session_end', 'transaction']) {
      final session = event != 'transaction';
      final table = session ? 'sessions' : 'entries';
      final when = event == 'session_end'
          ? 'AFTER UPDATE OF ended ON sessions WHEN OLD.ended IS NULL AND NEW.ended IS NOT NULL AND $enabled'
          : 'AFTER INSERT ON $table WHEN $enabled';
      final time = event == 'session_start'
          ? 'NEW.started'
          : event == 'session_end'
          ? 'NEW.ended'
          : "CAST(strftime('%s','now') AS INTEGER) * 1000";
      final action = event == 'session_start'
          ? "'clock_in'"
          : event == 'session_end'
          ? "'clock_out'"
          : 'NEW.kind';
      final title = event == 'session_start'
          ? "'Clocked in'"
          : event == 'session_end'
          ? "'Clocked out'"
          : "CASE NEW.kind WHEN 'expense' THEN 'Purchased ' || CASE WHEN NEW.note != '' THEN NEW.note ELSE NEW.category END WHEN 'income' THEN 'Received income' ELSE 'Saved money' END";
      final details = session
          ? "json_object('kind', NEW.kind, 'note', NEW.note, 'position', $position)"
          : "json_object('currency', NEW.currency, 'amount', NEW.amount, 'method', NEW.method, 'note', NEW.note, 'position', $position)";
      await customStatement(
        "CREATE TRIGGER IF NOT EXISTS log_$event $when BEGIN INSERT OR IGNORE INTO activity_logs VALUES ('$event:' || NEW.id, $time, $action, $title, $place, $details); END",
      );
    }
  }

  Stream<List<Map<String, dynamic>>> watchActivityLogs() => customSelect(
    'SELECT * FROM activity_logs ORDER BY time DESC LIMIT 1000',
    readsFrom: {preferences, sessions, entries},
  ).watch().map((rows) => rows.map((r) => r.data).toList());
  Future<void> addActivity(Map<String, dynamic> event) async {
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
  }

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

  Future<Map<String, String>> readPreferences() async => {
    for (final p in await select(preferences).get()) p.key: p.value,
  };
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
  Future<Session> clockIn(String note) => transaction(() async {
    final existing =
        await (select(sessions)..where(
              (s) => s.ended.isNull() | s.day.equals(dayKey(DateTime.now())),
            ))
            .get();
    if (existing.isNotEmpty) {
      throw StateError(
        'A session already exists for today. Open it to edit or resume your records.',
      );
    }
    final s = Session(
      id: newId(),
      day: dayKey(DateTime.now()),
      kind: 'OJT',
      started: DateTime.now().millisecondsSinceEpoch,
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
  Future<String> backup() async {
    final d = await readAll();
    return jsonEncode({
      'format': 'frekihub',
      'version': 1,
      'sessions': d.sessions.map((s) => s.toJson()).toList(),
      'entries': d.entries.map((e) => e.toJson()).toList(),
      'rules': d.rules.map((r) => r.toJson()).toList(),
      'preferences': d.prefs,
      'activityLogs': (await customSelect(
        'SELECT * FROM activity_logs ORDER BY time',
      ).get()).map((r) => r.data).toList(),
    });
  }

  Future<void> restore(String source) async {
    final raw = jsonDecode(source);
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
      if (s.started < 0 || (s.ended != null && s.ended! < s.started)) {
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
      for (final log in (raw['activityLogs'] as List? ?? const [])) {
        final item = Map<String, dynamic>.from(log as Map);
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
  Projection(this.rule, this.day, this.amount, this.status);
  String get key => '${rule.id}:$day';
}

List<Projection> project(AppData data, DateTime from, DateTime until) {
  final result = <Projection>[];
  final recordedOccurrences = data.entries.map((e) => e.occurrence).toSet();
  final monthlyTotals = <String, (int, int)>{};
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
      final totals = monthlyTotals.putIfAbsent(
        month,
        () => (
          data.total('income', month: month),
          data.total('expense', month: month),
        ),
      );
      final income = totals.$1;
      final expenses = totals.$2;
      final base = switch (r.basis) {
        'income' => income,
        'expenses' => expenses,
        'net' => max(0, income - expenses),
        _ => 0,
      };
      final amount = r.basis == 'fixed'
          ? r.amount * r.quantity
          : ((BigInt.from(base) *
                            BigInt.from(r.amount) *
                            BigInt.from(r.quantity) +
                        BigInt.from(5000)) ~/
                    BigInt.from(10000))
                .toInt();
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
              : 'planned',
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
