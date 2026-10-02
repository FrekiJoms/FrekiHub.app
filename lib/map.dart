part of 'screens.dart';

class MapScreen extends ConsumerStatefulWidget {
  final AppData data;
  final TileProvider? tileProvider;
  const MapScreen({super.key, required this.data, this.tileProvider});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final controller = MapController();
  late final tileProvider =
      widget.tileProvider ??
      NetworkTileProvider(
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 128 * 1024 * 1024,
        ),
      );
  StreamSubscription<List<Map<String, dynamic>>>? subscription;
  Timer? contextTimer;
  late String period = widget.data.prefs['mapPeriod'] ?? 'day';
  late DateTime date =
      DateTime.tryParse(widget.data.prefs['mapDate'] ?? '') ?? DateTime.now();
  late MapRange range = MapRange.period(period, date);
  late bool trace = widget.data.prefs['mapTrace'] == 'true';
  final categories = <String>{'Sessions', 'Finance', 'Locations', 'Other'};
  Set<String> selected = {};
  List<MapRecord> records = [];
  List<Map<String, dynamic>> previousRows = [];
  bool ready = false, loading = true, tileError = false;
  String? loadError;
  String lastContext = '';
  static const colors = <String, Color>{
    'Sessions': Color(0xFF456FE8),
    'Finance': Color(0xFF087C5A),
    'Locations': Color(0xFFB77519),
    'Other': Color(0xFF8650BD),
  };
  static const icons = <String, IconData>{
    'Sessions': LucideIcons.clock3,
    'Finance': LucideIcons.wallet,
    'Locations': LucideIcons.mapPin,
    'Other': LucideIcons.layers,
  };
  List<MapRecord> get visible =>
      records.where((r) => categories.contains(r.category)).toList();
  List<MapRecord> get traced => visible
      .where((r) => selected.isEmpty || selected.contains(r.id))
      .toList();

  @override
  void initState() {
    super.initState();
    if (!['day', 'week', 'month', 'year', 'custom'].contains(period)) {
      period = 'day';
    }
    if (period == 'custom') {
      final from = DateTime.tryParse(widget.data.prefs['mapFrom'] ?? '');
      final until = DateTime.tryParse(widget.data.prefs['mapUntil'] ?? '');
      if (from != null && until != null && until.isAfter(from)) {
        range = MapRange(from, until);
      } else {
        period = 'day';
        range = MapRange.period(period, date);
      }
    }
    watch();
  }

  void watch() {
    subscription?.cancel();
    loading = true;
    loadError = null;
    records = [];
    subscription = ref
        .read(databaseProvider)
        .watchMapLogs(range.from, range.until)
        .listen(
          (rows) {
            if (!mounted) return;
            // Preferences also wake the raw-table stream. Panning updates map
            // context, but must not reparse every log or rebuild all markers.
            if (!loading &&
                rows.length == previousRows.length &&
                Iterable<int>.generate(rows.length).every(
                  (i) => const [
                    'id',
                    'time',
                    'action',
                    'title',
                    'location',
                    'details',
                  ].every((key) => rows[i][key] == previousRows[i][key]),
                )) {
              return;
            }
            previousRows = rows;
            final next = rows
                .map(MapRecord.parse)
                .whereType<MapRecord>()
                .toList();
            final firstLoad = loading;
            setState(() {
              records = next;
              selected.removeWhere((id) => !records.any((r) => r.id == id));
              loading = false;
            });
            publishContext();
            if (firstLoad && ready && visible.isNotEmpty) fit();
          },
          onError: (Object _) {
            if (mounted) {
              setState(() {
                loading = false;
                loadError = 'Could not load location records';
              });
            }
          },
        );
  }

  void publishContext() {
    if (!mounted) return;
    contextTimer?.cancel();
    contextTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final camera = ready ? controller.camera : null;
      final payload = jsonEncode({
        'map.period': period,
        'map.from': dayKey(range.from),
        'map.until': dayKey(range.until),
        'map.trace_enabled': trace,
        'map.visible_count': visible.length,
        'map.selected_count': traced
            .where((r) => selected.contains(r.id))
            .length,
        'map.center_lat': camera?.center.latitude ?? 0,
        'map.center_lng': camera?.center.longitude ?? 0,
        'map.zoom': camera?.zoom ?? 2,
      });
      if (payload == lastContext) return;
      lastContext = payload;
      unawaited(
        ref
            .read(databaseProvider)
            .pref('mapContext', payload)
            .catchError((Object _) {}),
      );
    });
  }

  Future<void> saveView() async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.pref('mapPeriod', period);
      await db.pref('mapDate', dayKey(date));
      await db.pref('mapFrom', range.from.toIso8601String());
      await db.pref('mapUntil', range.until.toIso8601String());
      await db.pref('mapTrace', trace);
    });
    publishContext();
  }

  void fit() {
    final points = traced;
    if (!ready || points.isEmpty) return;
    final coordinates = points.map((r) => LatLng(r.lat, r.lng)).toList();
    if (coordinates.every((p) => p == coordinates.first)) {
      controller.move(coordinates.first, 15);
    } else {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(coordinates),
          padding: EdgeInsets.fromLTRB(
            56,
            math.min(190, MediaQuery.sizeOf(context).height * .3),
            56,
            math.min(
              250 + MediaQuery.paddingOf(context).bottom,
              MediaQuery.sizeOf(context).height * .35,
            ),
          ),
          maxZoom: 16,
        ),
      );
    }
    publishContext();
  }

  Future<void> choosePeriod() async {
    final value = await panel<String>(
      context,
      _ChoiceSheet(
        title: 'Timeline',
        selected: period,
        values: const ['day', 'week', 'month', 'year', 'custom'],
      ),
    );
    if (!mounted || value == null) return;
    if (value == 'custom') {
      final from = await showWheelDatePicker(
        context: context,
        initialDate: range.from,
        firstDate: DateTime(1970),
        lastDate: DateTime(2100),
      );
      if (!mounted || from == null) return;
      final until = await showWheelDatePicker(
        context: context,
        initialDate:
            range.until.subtract(const Duration(days: 1)).isBefore(from)
            ? from
            : range.until.subtract(const Duration(days: 1)),
        firstDate: from,
        lastDate: DateTime(2100),
      );
      if (!mounted || until == null) return;
      setState(() {
        period = value;
        date = from;
        range = MapRange(
          from,
          DateTime(until.year, until.month, until.day + 1),
        );
        selected.clear();
        watch();
      });
    } else {
      setState(() {
        period = value;
        range = MapRange.period(period, date);
        selected.clear();
        watch();
      });
    }
    await guarded(context, saveView);
  }

  void shift(int direction) {
    setState(() {
      if (period == 'custom') {
        final days = range.until.difference(range.from).inDays;
        final from = DateTime(
          range.from.year,
          range.from.month,
          range.from.day + days * direction,
        );
        final until = DateTime(
          range.until.year,
          range.until.month,
          range.until.day + days * direction,
        );
        range = MapRange(from, until);
        date = from;
      } else {
        date = switch (period) {
          'year' => DateTime(date.year + direction, date.month, 1),
          'month' => DateTime(date.year, date.month + direction, 1),
          'week' => DateTime(date.year, date.month, date.day + 7 * direction),
          _ => DateTime(date.year, date.month, date.day + direction),
        };
        range = MapRange.period(period, date);
      }
      selected.clear();
      watch();
    });
    unawaited(guarded(context, saveView));
  }

  Future<void> selectDate() async {
    if (period == 'custom') {
      await choosePeriod();
      return;
    }
    final result = await showWheelDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (!mounted || result == null) return;
    setState(() {
      date = result;
      range = MapRange.period(period, date);
      selected.clear();
      watch();
    });
    await guarded(context, saveView);
  }

  Future<void> showRecords([List<MapRecord>? group]) async {
    final items = (group ?? visible).reversed.toList();
    final result = await panel<Set<String>>(
      context,
      _MapLogSheet(records: items, selected: selected),
    );
    if (!mounted || result == null) return;
    setState(() => selected = result);
    publishContext();
    if (selected.isNotEmpty) fit();
  }

  Widget control(
    String label,
    IconData icon,
    VoidCallback action, {
    bool active = false,
  }) => IconButton(
    tooltip: label,
    onPressed: withFeedback(action),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: active ? Theme.of(context).colorScheme.primary : null,
    ),
    icon: Icon(icon, size: 21),
  );
  @override
  Widget build(BuildContext c) {
    final shown = visible;
    final route = traced;
    final groups = <String, List<MapRecord>>{};
    for (final record in shown) {
      groups
          .putIfAbsent(
            '${record.lat.toStringAsFixed(5)},${record.lng.toStringAsFixed(5)}',
            () => [],
          )
          .add(record);
    }
    final bottom = MediaQuery.paddingOf(c).bottom;
    final dateLabel = period == 'day'
        ? DateFormat('EEE, d MMM yyyy').format(range.from)
        : period == 'month'
        ? DateFormat('MMMM yyyy').format(range.from)
        : period == 'year'
        ? '${range.from.year}'
        : '${DateFormat('d MMM').format(range.from)} – ${DateFormat('d MMM yyyy').format(range.until.subtract(const Duration(days: 1)))}';
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 2,
              minZoom: 2,
              maxZoom: 19,
              interactionOptions: InteractionOptions(
                flags:
                    InteractiveFlag.all &
                    ~InteractiveFlag.rotate &
                    (MediaQuery.disableAnimationsOf(c)
                        ? ~InteractiveFlag.flingAnimation
                        : -1),
                doubleTapZoomDuration: Motion.duration(c, 200),
                doubleTapZoomCurve: Motion.curve,
              ),
              onMapReady: () {
                ready = true;
                if (shown.isNotEmpty) fit();
                publishContext();
              },
              onPositionChanged: (_, _) => publishContext(),
            ),
            children: [
              TileLayer(
                tileProvider: tileProvider,
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.frekihub.freki_hub',
                tileDisplay: TileDisplay.instantaneous(),
                errorTileCallback: (_, _, _) {
                  if (!tileError && mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => tileError = true);
                    });
                  }
                },
              ),
              if (trace && route.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route.map((r) => LatLng(r.lat, r.lng)).toList(),
                      color: const Color(0xFF456FE8),
                      strokeWidth: 3,
                      pattern: StrokePattern.dashed(segments: [8, 5]),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: groups.values.map((items) {
                  final record = items.last;
                  final chosen = items.any((r) => selected.contains(r.id));
                  return Marker(
                    point: LatLng(record.lat, record.lng),
                    width: 48,
                    height: 48,
                    child: Semantics(
                      label:
                          '${record.category}: ${record.title}, ${items.length} records at ${record.location}',
                      button: true,
                      selected: chosen,
                      child: GestureDetector(
                        onTap: withFeedback(() => showRecords(items)),
                        child: Center(
                          child: Container(
                            width: items.length > 1 ? 32 : 22,
                            height: items.length > 1 ? 32 : 22,
                            decoration: BoxDecoration(
                              color: colors[record.category],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: chosen
                                    ? const Color(0xFF172034)
                                    : Colors.white,
                                width: chosen ? 4 : 3,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6),
                              ],
                            ),
                            child: items.length > 1
                                ? Center(
                                    child: Text(
                                      '${items.length}',
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Positioned(
          top: 80,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Chrome(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        control(
                          'Previous timeline',
                          LucideIcons.chevronLeft,
                          () => shift(-1),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: withFeedback(selectDate),
                            child: Text(dateLabel, textAlign: TextAlign.center),
                          ),
                        ),
                        control(
                          'Next timeline',
                          LucideIcons.chevronRight,
                          () => shift(1),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: withFeedback(choosePeriod),
                            icon: const Icon(
                              LucideIcons.slidersHorizontal,
                              size: 16,
                            ),
                            label: Text(
                              '${period[0].toUpperCase()}${period.substring(1)}',
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: withFeedback(() => showRecords()),
                            icon: const Icon(LucideIcons.listFilter, size: 16),
                            label: Text('${shown.length} logs'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 218 + bottom,
          child: Chrome(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                control('Fit recorded locations', LucideIcons.scan, fit),
                control(
                  trace
                      ? 'Hide chronological trace'
                      : 'Trace selected logs, or all logs',
                  LucideIcons.route,
                  () {
                    setState(() => trace = !trace);
                    unawaited(guarded(c, saveView));
                  },
                  active: trace,
                ),
                control('Zoom in', LucideIcons.plus, () {
                  if (ready) {
                    controller.move(
                      controller.camera.center,
                      math.min(19, controller.camera.zoom + 1),
                    );
                  }
                }),
                control('Zoom out', LucideIcons.minus, () {
                  if (ready) {
                    controller.move(
                      controller.camera.center,
                      math.max(2, controller.camera.zoom - 1),
                    );
                  }
                }),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 114 + bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Chrome(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: colors.entries
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: FilterChip(
                                  label: Text(entry.key),
                                  avatar: Icon(
                                    icons[entry.key],
                                    size: 16,
                                    color: entry.value,
                                  ),
                                  selected: categories.contains(entry.key),
                                  onSelected: (_) {
                                    ActionFeedback.tap();
                                    setState(() {
                                      if (!categories.remove(entry.key)) {
                                        categories.add(entry.key);
                                      }
                                    });
                                    publishContext();
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    Text(
                      loading
                          ? 'Loading recorded locations…'
                          : loadError ??
                                (shown.isEmpty
                                    ? 'No located logs in this timeline'
                                    : trace
                                    ? '${route.length} samples · straight-line trace'
                                    : '${selected.length} selected · tap a dot for details'),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                    if (tileError)
                      Text(
                        'Map tiles unavailable · saved dots remain visible',
                        textAlign: TextAlign.center,
                        style: Theme.of(c).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 88 + bottom,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: Theme.of(c).colorScheme.surface,
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    contextTimer?.cancel();
    controller.dispose();
    super.dispose();
  }
}

class _MapLogSheet extends StatefulWidget {
  final List<MapRecord> records;
  final Set<String> selected;
  const _MapLogSheet({required this.records, required this.selected});
  @override
  State<_MapLogSheet> createState() => _MapLogSheetState();
}

class _MapLogSheetState extends State<_MapLogSheet> {
  late final Set<String> selected = {...widget.selected};
  @override
  Widget build(BuildContext c) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(c).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Located logs',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: withFeedback(() => Navigator.pop(c, selected)),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: withFeedback(
                    () => setState(
                      () => selected.addAll(widget.records.map((r) => r.id)),
                    ),
                  ),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: withFeedback(() => setState(selected.clear)),
                  child: const Text('Clear'),
                ),
                Expanded(
                  child: Text(
                    '${selected.length} selected',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No selection traces all filtered logs. Expand a record for its stored details.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.records.isEmpty
                ? ListView(
                    children: const [
                      Center(child: Text('No records with a usable location')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: widget.records.length,
                    itemBuilder: (c, i) {
                      final record = widget.records[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Surface(
                          padding: EdgeInsets.zero,
                          child: ExpansionTile(
                            leading: Checkbox(
                              value: selected.contains(record.id),
                              activeColor:
                                  _MapScreenState.colors[record.category],
                              semanticLabel: 'Select ${record.title}',
                              onChanged: (_) {
                                ActionFeedback.tap();
                                setState(() {
                                  if (!selected.remove(record.id)) {
                                    selected.add(record.id);
                                  }
                                });
                              },
                            ),
                            title: Text(
                              record.title,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              '${record.category} · ${record.location}\n${DateFormat('d MMM yyyy, HH:mm:ss').format(record.time)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SelectableText(
                                  [
                                    'Coordinates: ${record.lat.toStringAsFixed(6)}, ${record.lng.toStringAsFixed(6)}',
                                    if (record.position['accuracy'] != null)
                                      'Accuracy: ±${record.position['accuracy']} m',
                                    if (record.position['locationTime'] is int)
                                      'Sampled: ${DateFormat('d MMM yyyy, HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(record.position['locationTime'] as int))}',
                                    if (record.details['amount'] != null &&
                                        record.details['currency'] is String)
                                      'Amount: ${money(record.details['amount'] is int ? record.details['amount'] as int : parseMoney('${record.details['amount']}', record.details['currency'] as String), record.details['currency'] as String)}',
                                    for (final entry
                                        in record.details.entries.where(
                                          (e) => ![
                                            'position',
                                            'lat',
                                            'lng',
                                            'accuracy',
                                            'locationTime',
                                            'id',
                                            'time',
                                            'title',
                                            'location',
                                            'amount',
                                            'currency',
                                          ].contains(e.key),
                                        ))
                                      '${entry.key}: ${entry.value}',
                                  ].join('\n'),
                                  style: Theme.of(c).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
