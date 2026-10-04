import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/map_records.dart';
import 'package:freki_hub/rule_language.dart';

void main() {
  test(
    'Foreground user fix rejects stale, coarse, future and invalid positions',
    () {
      final now = DateTime(2026, 10, 4, 12);
      final fix = {
        'lat': 14.5,
        'lng': 121.0,
        'accuracy': 12.0,
        'locationTime': now.millisecondsSinceEpoch,
      };
      expect(MapUserLocation.parse(fix, now)?.lat, 14.5);
      for (final invalid in [
        {...fix, 'lat': 91},
        {...fix, 'lng': double.nan},
        {...fix, 'accuracy': 101},
        {...fix, 'accuracy': -1},
        {...fix, 'locationTime': now.millisecondsSinceEpoch - 120001},
        {...fix, 'locationTime': now.millisecondsSinceEpoch + 1001},
        {'lat': 14.5, 'lng': 121.0},
      ]) {
        expect(MapUserLocation.parse(invalid, now), isNull);
      }
    },
  );

  test('Location records preserve nested finance/session positions and reject stale or invalid coordinates', () {
    final time = DateTime(2026, 10, 2, 8).millisecondsSinceEpoch;
    Map<String, dynamic> row(dynamic position, {String action = 'purchase'}) =>
        {
          'id': '1',
          'time': time,
          'action': action,
          'title': 'Purchased lunch',
          'location': 'Cafe',
          'details': jsonEncode({
            'position': position,
            'currency': 'PHP',
            'amount': 12000,
          }),
        };
    final position = {'lat': 14.5, 'lng': 121.0, 'locationTime': time - 60000};
    final record = MapRecord.parse(row(jsonEncode(position)))!;
    expect(record.category, 'Finance');
    expect(record.lat, 14.5);
    expect(record.details['amount'], 12000);
    expect(
      MapRecord.parse(row(position, action: 'auto_clock_in'))!.category,
      'Sessions',
    );
    expect(
      MapRecord.parse(row(position, action: 'new_action'))!.category,
      'Other',
    );
    expect(
      MapRecord.parse(row({...position, 'locationTime': time - 120001})),
      isNull,
    );
    expect(MapRecord.parse(row({...position, 'lat': 91})), isNull);
    expect(MapRecord.parse(row('broken JSON')), isNull);
  });
  test('Timeline queries include all records, exclude the end boundary and keep chronological order', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.readAll();
    final range = MapRange.period('day', DateTime(2026, 10, 2));
    await db.customStatement(
      'INSERT INTO activity_logs VALUES (?, ?, ?, ?, ?, ?)',
      [
        'end',
        range.until.millisecondsSinceEpoch,
        'location',
        'Outside range',
        'Cafe',
        '{}',
      ],
    );
    await db.transaction(() async {
      for (int i = 1001; i >= 0; i--) {
        await db.customStatement(
          'INSERT INTO activity_logs VALUES (?, ?, ?, ?, ?, ?)',
          [
            '$i',
            range.from.millisecondsSinceEpoch + i * 1000,
            'location',
            'Visited',
            'Cafe',
            '{}',
          ],
        );
      }
    });
    final rows = await db.watchMapLogs(range.from, range.until).first;
    expect(rows.length, 1002);
    expect(rows.first['id'], '0');
    expect(rows.last['id'], '1001');
    expect(
      MapRange.period('week', DateTime(2026, 10, 2)).from,
      DateTime(2026, 9, 28),
    );
    expect(
      MapRange.period('month', DateTime(2026, 12, 8)).until,
      DateTime(2027, 1),
    );
    expect(
      MapRange.period('year', DateTime(2026, 12, 8)).until,
      DateTime(2027),
    );
  });
  test(
    'Map rule target accepts typed fields and rejects inappropriate actions',
    () {
      RuleCompiler.compile(
        'target == map_page { if (map.from_epoch > 0 && map.until_epoch > 0) { log("Range"); } }',
      );
      expect(
        () => RuleCompiler.compile(
          'target == map_page { if (map.from_epoch == "today") { log("Invalid"); } }',
        ),
        throwsFormatException,
      );
      RuleCompiler.compile(
        'target == map_page { if (data.get("map.visible_count") > 0 && data.get("map.trace_enabled") == true) { app.toast("Trace is visible"); } }',
      );
      expect(
        () => RuleCompiler.compile(
          'target == map_page { if (true) { session.clock_out(); } }',
        ),
        throwsFormatException,
      );
      expect(
        () => RuleCompiler.compile(
          'target == map_page { if (data.get("map.zoom") == "near") { log("Invalid"); } }',
        ),
        throwsFormatException,
      );
      RuleCompiler.compile(
        'target == map_page { if (map.unlocated_count > 0 && map.total_count > 1) { log("Missing locations"); } }',
      );
      expect(
        () => RuleCompiler.compile(
          'target == map_page { if (map.unlocated_count == "none") { log("Invalid"); } }',
        ),
        throwsFormatException,
      );
      final snapshot = RuleCatalog.snapshot(
        AppData([], [], [], {
          'mapContext': jsonEncode({
            'map.visible_count': 4,
            'map.total_count': 7,
            'map.unlocated_count': 3,
            'map.trace_enabled': true,
          }),
        }),
      );
      expect(snapshot['map.visible_count'], 4);
      expect(snapshot['map.total_count'], 7);
      expect(snapshot['map.unlocated_count'], 3);
      expect(snapshot['map.trace_enabled'], true);
      final stored = RuleCatalog.snapshot(
        AppData([], [], [], {
          'mapFrom': '2026-10-04T09:30:00',
          'mapUntil': '2026-10-04T12:01:00',
        }),
      );
      expect(
        stored['map.from_epoch'],
        DateTime(2026, 10, 4, 9, 30).millisecondsSinceEpoch,
      );
      expect(
        stored['map.until_epoch'],
        DateTime(2026, 10, 4, 12, 1).millisecondsSinceEpoch,
      );
    },
  );
}
