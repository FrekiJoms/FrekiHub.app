import 'dart:convert';
import 'dart:math' as math;

/// Zoom-dependent clustering radius in screen pixels so markers progressively
/// separate as the user zooms in without overlapping badges.
double clusterRadiusPx(int zoom) {
  final z = zoom.clamp(2, 19);
  if (z <= 10) return 62;
  if (z <= 13) return 50;
  return switch (z) {
    14 => 42,
    15 => 34,
    16 => 26,
    17 => 18,
    18 => 10,
    _ => 4,
  };
}

/// Screen-sized spatial clusters retain every original record and its actual
/// position without overlapping cluster badges. Linear in record count.
List<List<MapRecord>> clusterMapRecords(Iterable<MapRecord> records, int zoom) {
  final z = zoom.clamp(2, 19);
  final scale = 256.0 * math.pow(2, z);
  final radius = clusterRadiusPx(z);
  final radiusSq = radius * radius;
  final clusters = <List<MapRecord>>[];
  final anchors = <(double, double)>[];
  final grid = <(int, int), List<int>>{};

  for (final record in records) {
    final latitude = record.lat.clamp(-85.05112878, 85.05112878);
    final sinLatitude = math.sin(latitude * math.pi / 180);
    final x = (record.lng + 180) / 360 * scale;
    final y =
        (0.5 -
            math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        scale;
    final cellX = (x / radius).floor();
    final cellY = (y / radius).floor();
    int? match;
    var bestDistSq = radiusSq;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final candidates = grid[(cellX + dx, cellY + dy)];
        if (candidates == null) continue;
        for (final idx in candidates) {
          final (ax, ay) = anchors[idx];
          final dSq = (x - ax) * (x - ax) + (y - ay) * (y - ay);
          if (dSq <= bestDistSq) {
            bestDistSq = dSq;
            match = idx;
          }
        }
      }
    }
    if (match != null) {
      clusters[match].add(record);
    } else {
      final idx = clusters.length;
      clusters.add([record]);
      anchors.add((x, y));
      grid.putIfAbsent((cellX, cellY), () => []).add(idx);
    }
  }
  return clusters;
}

({double lat, double lng}) clusterCenter(List<MapRecord> items) {
  if (items.length == 1) return (lat: items.first.lat, lng: items.first.lng);
  var sumLat = 0.0;
  var sumLng = 0.0;
  for (final item in items) {
    sumLat += item.lat;
    sumLng += item.lng;
  }
  return (lat: sumLat / items.length, lng: sumLng / items.length);
}

class MapRouteGroup {
  final String id;
  final List<MapRecord> records;
  const MapRouteGroup({required this.id, required this.records});
  DateTime get start => records.first.time;
  DateTime get end => records.last.time;
}

/// Splits chronological records into coherent route segments without connecting
/// unrelated days or sessions separated by large gaps (> 4 hours).
List<MapRouteGroup> splitMapRoutes(
  List<MapRecord> records, {
  Duration maxGap = const Duration(hours: 4),
}) {
  if (records.isEmpty) return const [];
  final sorted = [...records]..sort((a, b) => a.time.compareTo(b.time));
  final groups = <MapRouteGroup>[];
  var current = <MapRecord>[sorted.first];
  for (var i = 1; i < sorted.length; i++) {
    final prev = sorted[i - 1];
    final next = sorted[i];
    final sameDay =
        prev.time.year == next.time.year &&
        prev.time.month == next.time.month &&
        prev.time.day == next.time.day;
    final withinGap = next.time.difference(prev.time) <= maxGap;
    if (sameDay && withinGap) {
      current.add(next);
    } else {
      if (current.length > 1) {
        groups.add(MapRouteGroup(id: current.first.id, records: current));
      }
      current = [next];
    }
  }
  if (current.length > 1) {
    groups.add(MapRouteGroup(id: current.first.id, records: current));
  }
  return groups;
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
