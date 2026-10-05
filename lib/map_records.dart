import 'dart:convert';
import 'dart:math' as math;

/// Screen-sized clusters retain every original record and its actual position.
/// Bucketing is linear in record count and changes only at whole zoom levels.
List<List<MapRecord>> clusterMapRecords(Iterable<MapRecord> records, int zoom) {
  final scale = 256 * math.pow(2, zoom.clamp(2, 19));
  final groups = <(int, int), List<MapRecord>>{};
  for (final record in records) {
    final latitude = record.lat.clamp(-85.05112878, 85.05112878);
    final sinLatitude = math.sin(latitude * math.pi / 180);
    final x = (record.lng + 180) / 360 * scale;
    final y =
        (0.5 -
            math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        scale;
    final cell = ((x / 54).floor(), (y / 54).floor());
    groups.putIfAbsent(cell, () => []).add(record);
  }
  return groups.values.toList();
}

/// Calendar-aligned local-time ranges, with an exclusive end.
class MapRange {
  final DateTime from, until;
  const MapRange(this.from, this.until);
  factory MapRange.period(String period, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return switch (period) {
      'week' => MapRange(
        DateTime(day.year, day.month, day.day - day.weekday + 1),
        DateTime(day.year, day.month, day.day + 8 - day.weekday),
      ),
      'month' => MapRange(
        DateTime(date.year, date.month),
        DateTime(date.year, date.month + 1),
      ),
      'year' => MapRange(DateTime(date.year), DateTime(date.year + 1)),
      _ => MapRange(day, DateTime(date.year, date.month, date.day + 1)),
    };
  }
}

class MapRecord {
  final Map<String, dynamic> row, details, position;
  final double lat, lng;
  final DateTime time;
  const MapRecord(
    this.row,
    this.details,
    this.position,
    this.lat,
    this.lng,
    this.time,
  );
  String get id => row['id'].toString();
  String get title => row['title']?.toString() ?? 'Activity';
  String get location => row['location']?.toString() ?? 'Recorded location';
  String get category {
    final action = row['action']?.toString() ?? '';
    if (action.contains('clock') || action.startsWith('session')) {
      return 'Sessions';
    }
    if (['purchase', 'expense', 'income', 'savings'].contains(action)) {
      return 'Finance';
    }
    if (action.startsWith('location')) return 'Locations';
    return 'Other';
  }

  static Map<String, dynamic> decode(dynamic value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static MapRecord? parse(Map<String, dynamic> row) {
    final details = decode(row['details']);
    final position = details.containsKey('position')
        ? decode(details['position'])
        : details;
    final lat = num.tryParse('${position['lat']}')?.toDouble();
    final lng = num.tryParse('${position['lng']}')?.toDouble();
    final time = int.tryParse('${row['time']}');
    if (lat == null ||
        lng == null ||
        time == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    final sample = int.tryParse('${position['locationTime']}');
    if (sample != null && (time - sample > 120000 || sample - time > 1000)) {
      return null;
    }
    if (row['location'] == 'Location unavailable' && sample == null) {
      return null;
    }
    return MapRecord(
      row,
      details,
      position,
      lat,
      lng,
      DateTime.fromMillisecondsSinceEpoch(time),
    );
  }
}

/// A foreground Map fix, independent of saved log coordinates.
class MapUserLocation {
  final double lat, lng, accuracy;
  final int sampled;
  const MapUserLocation(this.lat, this.lng, this.accuracy, this.sampled);
  static MapUserLocation? parse(dynamic value, DateTime now) {
    final data = MapRecord.decode(value);
    final lat = num.tryParse('${data['lat']}')?.toDouble();
    final lng = num.tryParse('${data['lng']}')?.toDouble();
    final accuracy = num.tryParse('${data['accuracy']}')?.toDouble();
    final sampled = int.tryParse('${data['locationTime']}');
    if (lat == null ||
        lng == null ||
        accuracy == null ||
        sampled == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        !accuracy.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        accuracy < 0 ||
        now.millisecondsSinceEpoch - sampled > 120000 ||
        sampled - now.millisecondsSinceEpoch > 1000) {
      return null;
    }
    return MapUserLocation(lat, lng, accuracy, sampled);
  }
}
