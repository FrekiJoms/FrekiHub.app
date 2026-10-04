part of 'screens.dart';

class MapScreen extends ConsumerStatefulWidget {
  final AppData data;
  final TileProvider? tileProvider;
  final String apiKey;
  const MapScreen({
    super.key,
    required this.data,
    this.tileProvider,
    this.apiKey = const String.fromEnvironment('GEOAPIFY_API_KEY'),
  });
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final controller = MapController();
  final tileReset = StreamController<void>.broadcast();
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
  List<Map<String, dynamic>> unlocated = [];
  List<Map<String, dynamic>> previousRows = [];
  int queryGeneration = 0;
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
    final generation = ++queryGeneration;
    subscription?.cancel();
    loading = true;
    loadError = null;
    records = [];
    subscription = ref
        .read(databaseProvider)
        .watchMapLogs(range.from, range.until)
        .listen(
          (rows) {
            if (!mounted || generation != queryGeneration) return;
            // Preferences also wake the raw-table stream. Panning updates map
            // context, but must not reparse every log or rebuild all markers.
            if (!loading &&
                loadError == null &&
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
            final next = <MapRecord>[];
            final without = <Map<String, dynamic>>[];
            for (final row in rows) {
              final record = MapRecord.parse(row);
              if (record == null) {
                without.add(row);
              } else {
                next.add(record);
              }
            }
            final firstLoad = loading || records.isEmpty;
            setState(() {
              records = next;
              unlocated = without;
              selected.removeWhere((id) => !records.any((r) => r.id == id));
              loading = false;
              loadError = null;
            });
            publishContext();
            if (firstLoad && ready && visible.isNotEmpty) fit();
          },
          onError: (Object _) {
            if (mounted && generation == queryGeneration) {
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
        'map.from_epoch': range.from.millisecondsSinceEpoch,
        'map.until_epoch': range.until.millisecondsSinceEpoch,
        'map.trace_enabled': trace,
        'map.visible_count': visible.length,
        'map.total_count': previousRows.length,
        'map.unlocated_count': unlocated.length,
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

  Future<void> choosePeriod(String value) async {
    MapRange? custom;
    if (value == 'custom') {
      custom = await panel<MapRange>(context, _MapRangeSheet(initial: range));
      if (!mounted || custom == null) return;
    }
    setState(() {
      period = value;
      if (custom != null) date = custom.from;
      range = custom ?? MapRange.period(period, date);
      selected.clear();
      watch();
    });
    await guarded(context, saveView);
  }

  int shiftDirection = 1;
  void shift(int direction) {
    setState(() {
      shiftDirection = direction;
      if (period == 'custom') {
        final offset = range.until.difference(range.from) * direction;
        range = MapRange(range.from.add(offset), range.until.add(offset));
        date = range.from;
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
      await choosePeriod('custom');
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
      _MapLogSheet(
        records: items,
        selected: selected,
        unlocated: group == null ? unlocated : const [],
      ),
    );
    if (!mounted || result == null) return;
    setState(() => selected = result);
    publishContext();
    if (selected.isNotEmpty) fit();
  }

  List<Widget> mapActions() => [
    control(
      'Fit recorded locations',
      LucideIcons.scan,
      fit,
      enabled: ready && traced.isNotEmpty,
    ),
    control(
      trace ? 'Hide chronological trace' : 'Trace selected logs, or all logs',
      LucideIcons.route,
      () {
        setState(() => trace = !trace);
        unawaited(guarded(context, saveView));
      },
      active: trace,
    ),
    control('Zoom in', LucideIcons.plus, () {
      controller.move(
        controller.camera.center,
        math.min(19, controller.camera.zoom + 1),
      );
    }, enabled: ready),
    control('Zoom out', LucideIcons.minus, () {
      controller.move(
        controller.camera.center,
        math.max(2, controller.camera.zoom - 1),
      );
    }, enabled: ready),
  ];
  Widget control(
    String label,
    IconData icon,
    VoidCallback action, {
    bool? active,
    bool enabled = true,
  }) => IconButton(
    tooltip: label,
    isSelected: active,
    onPressed: withFeedback(enabled ? action : null),
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
      backgroundColor: Colors.transparent,
      foregroundColor: active == true
          ? Theme.of(context).colorScheme.onSurface
          : null,
    ),
    icon: Container(
      key: active == null ? null : const ValueKey('map-toggle-indicator'),
      width: 43,
      height: 43,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active == true
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .12)
            : Colors.transparent,
      ),
      child: Icon(icon, size: 18),
    ),
  );

  void retry() {
    if (loadError != null) setState(watch);
    if (tileError) {
      setState(() => tileError = false);
      tileReset.add(null);
    }
  }

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
        : period == 'custom'
        ? '${DateFormat('d MMM yyyy, HH:mm').format(range.from)} – ${DateFormat('d MMM yyyy, HH:mm').format(range.until.subtract(const Duration(minutes: 1)))}'
        : '${DateFormat('d MMM').format(range.from)} – ${DateFormat('d MMM yyyy').format(range.until.subtract(const Duration(days: 1)))}';
    final status = loading
        ? 'Loading recorded locations…'
        : loadError ??
              (shown.isEmpty
                  ? records.isNotEmpty
                        ? 'Categories hidden · select a legend'
                        : '${previousRows.length} logs · no usable locations'
                  : trace
                  ? '${route.length} samples · straight-line trace'
                  : '${shown.length} located · ${previousRows.length - records.length} without location');
    return LayoutBuilder(
      builder: (c, bounds) {
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
                    setState(() => ready = true);
                    if (shown.isNotEmpty) fit();
                    publishContext();
                  },
                  onPositionChanged: (_, _) => publishContext(),
                ),
                children: [
                  if (widget.apiKey.trim().isNotEmpty)
                    TileLayer(
                      reset: tileReset.stream,
                      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                      tileProvider: tileProvider,
                      urlTemplate:
                          'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=${Uri.encodeQueryComponent(widget.apiKey.trim())}',
                      userAgentPackageName: 'com.frekihub.freki_hub',
                      tileDisplay: TileDisplay.instantaneous(),
                      errorTileCallback: (_, _, _) {
                        if (!tileError && mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !tileError) {
                              setState(() => tileError = true);
                            }
                          });
                        }
                      },
                    ),
                  if (trace && route.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route
                              .map((r) => LatLng(r.lat, r.lng))
                              .toList(),
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
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: items.length > 1
                                    ? Center(
                                        child: Text(
                                          items.length > 99
                                              ? '99+'
                                              : '${items.length}',
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
              top: 16,
              left: 72,
              right: 72,
              child: Align(
                alignment: Alignment.topCenter,
                child: Chrome(
                  key: const ValueKey('map-date-pill'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 28,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Previous timeline',
                              disabledColor: Theme.of(c).colorScheme.onSurface
                                  .withValues(alpha: .3),
                              onPressed: period == 'custom'
                                  ? null
                                  : withFeedback(() => shift(-1)),
                              constraints: const BoxConstraints.tightFor(
                                width: 24,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                LucideIcons.chevronLeft,
                                size: 14,
                              ),
                            ),
                            Flexible(
                              child: InkWell(
                                onTap: withFeedback(selectDate),
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedSwitcher(
                                  duration: Motion.duration(c, 200),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position:
                                              Tween<Offset>(
                                                begin: Offset(
                                                  child.key ==
                                                          ValueKey(
                                                            '$period:${range.from}',
                                                          )
                                                      ? shiftDirection * .15
                                                      : -shiftDirection * .15,
                                                  0,
                                                ),
                                                end: Offset.zero,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Motion.curve,
                                                ),
                                              ),
                                          child: child,
                                        ),
                                      ),
                                  child: Text(
                                    period == 'year'
                                        ? '${date.year}'
                                        : period == 'day'
                                        ? DateFormat('d MMM').format(date)
                                        : period == 'week'
                                        ? DateFormat('d MMM').format(range.from)
                                        : period == 'custom'
                                        ? 'Custom range'
                                        : DateFormat.MMMM().format(date),
                                    key: ValueKey('$period:${range.from}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next timeline',
                              disabledColor: Theme.of(c).colorScheme.onSurface
                                  .withValues(alpha: .3),
                              onPressed: period == 'custom'
                                  ? null
                                  : withFeedback(() => shift(1)),
                              constraints: const BoxConstraints.tightFor(
                                width: 24,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                LucideIcons.chevronRight,
                                size: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 16,
                        child: Builder(
                          builder: (anchor) => Tooltip(
                            message: 'Timeline mode',
                            child: Semantics(
                              button: true,
                              label: 'Choose $period value',
                              hint: 'Long press to change timeline mode',
                              child: InkWell(
                                onTap: withFeedback(selectDate),
                                onLongPress: withFeedback(() async {
                                  final value = await showChoiceMenu<String>(
                                    anchor,
                                    choices: const {
                                      'day': 'Day',
                                      'week': 'Week',
                                      'month': 'Month',
                                      'year': 'Year',
                                      'custom': 'Custom',
                                    },
                                    selected: period,
                                  );
                                  if (mounted && value != null) {
                                    await choosePeriod(value);
                                  }
                                }),
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      period == 'day'
                                          ? 'Date'
                                          : '${period[0].toUpperCase()}${period.substring(1)}',
                                      style: const TextStyle(fontSize: 9),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      LucideIcons.chevronDown,
                                      size: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 76,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: Chrome(
                  key: const ValueKey('map-legends'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0, .055, .945, 1],
                    ).createShader(bounds),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: colors.entries
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: AnimatedOpacity(
                                  opacity: categories.contains(entry.key)
                                      ? 1
                                      : .4,
                                  duration: Motion.duration(c, 150),
                                  child: FilterChip(
                                    backgroundColor: Colors.transparent,
                                    selectedColor: Colors.transparent,
                                    side: BorderSide.none,
                                    label: Text(
                                      entry.key,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                    labelStyle: TextStyle(
                                      color: Theme.of(c).colorScheme.onSurface,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    showCheckmark: false,
                                    avatar: Icon(
                                      icons[entry.key],
                                      size: 13,
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
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 12,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chrome(
                      padding: EdgeInsets.zero,
                      child: control(
                        'Choose located logs',
                        LucideIcons.listFilter,
                        () => showRecords(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(
                          48,
                          bounds.maxHeight - 338 - bottom,
                        ),
                      ),
                      child: Chrome(
                        key: const ValueKey('map-tools-rail'),
                        padding: EdgeInsets.zero,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: mapActions(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 80,
              bottom: 112 + bottom,
              child: Center(
                child: Chrome(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: withFeedback(() => showRecords()),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                dateLabel,
                                style: const TextStyle(fontSize: 10),
                              ),
                              Text(
                                widget.apiKey.trim().isEmpty
                                    ? 'Basemap not configured · saved dots remain'
                                    : tileError
                                    ? 'Basemap unavailable · saved dots remain'
                                    : status,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: Theme.of(c).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (tileError || loadError != null)
                        control(
                          'Retry map loading',
                          LucideIcons.refreshCw,
                          retry,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 88 + bottom,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: Theme.of(c).colorScheme.surface,
                child: const Text(
                  'Powered by Geoapify · © OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    contextTimer?.cancel();
    tileReset.close();
    controller.dispose();
    super.dispose();
  }
}

class _MapLogSheet extends StatefulWidget {
  final List<MapRecord> records;
  final List<Map<String, dynamic>> unlocated;
  final Set<String> selected;
  const _MapLogSheet({
    required this.records,
    required this.selected,
    this.unlocated = const [],
  });
  @override
  State<_MapLogSheet> createState() => _MapLogSheetState();
}

class _MapLogSheetState extends State<_MapLogSheet> {
  late final Set<String> selected = {...widget.selected};
  @override
  Widget build(BuildContext c) => TextButtonTheme(
    data: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    child: PanelContent(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Timeline logs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
              'Only located logs can be selected or traced. Other saved logs remain listed below.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
      scrollable: true,
      child: widget.records.isEmpty && widget.unlocated.isEmpty
          ? ListView(
              children: const [
                Center(child: Text('No records with a usable location')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: widget.records.length + widget.unlocated.length,
              itemBuilder: (c, i) {
                if (i >= widget.records.length) {
                  final row = widget.unlocated[i - widget.records.length];
                  return ExpansionTile(
                    leading: const Icon(LucideIcons.mapPinOff),
                    title: Text(row['title']?.toString() ?? 'Activity'),
                    subtitle: const Text(
                      'No usable recorded location. The sample is missing, invalid or too old for this event.',
                    ),
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      SelectableText(
                        '${DateFormat('d MMM yyyy, HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(row['time'] as int))}\n${row['location']}\n${row['details']}',
                      ),
                    ],
                  );
                }
                final record = widget.records[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Surface(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      leading: Checkbox(
                        value: selected.contains(record.id),
                        activeColor: _MapScreenState.colors[record.category],
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
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                              for (final entry in record.details.entries.where(
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
  );
}

class _MapRangeSheet extends StatefulWidget {
  final MapRange initial;
  const _MapRangeSheet({required this.initial});
  @override
  State<_MapRangeSheet> createState() => _MapRangeSheetState();
}

class _MapRangeSheetState extends State<_MapRangeSheet> {
  late DateTime from = DateUtils.dateOnly(widget.initial.from);
  late DateTime through = DateUtils.dateOnly(
    widget.initial.until.subtract(const Duration(minutes: 1)),
  );
  late TimeOfDay startTime = TimeOfDay.fromDateTime(widget.initial.from);
  late TimeOfDay endTime = TimeOfDay.fromDateTime(
    widget.initial.until.subtract(const Duration(minutes: 1)),
  );
  late bool timed =
      widget.initial.from.hour != 0 ||
      widget.initial.from.minute != 0 ||
      widget.initial.until.hour != 0 ||
      widget.initial.until.minute != 0;
  MapRange get draft => MapRange(
    DateTime(
      from.year,
      from.month,
      from.day,
      timed ? startTime.hour : 0,
      timed ? startTime.minute : 0,
    ),
    timed
        ? DateTime(
            through.year,
            through.month,
            through.day,
            endTime.hour,
            endTime.minute + 1,
          )
        : DateTime(through.year, through.month, through.day + 1),
  );
  Future<void> pickDate(bool start) async {
    final picked = await showWheelDatePicker(
      context: context,
      initialDate: start ? from : through,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        from = picked;
      } else {
        through = picked;
      }
    });
  }

  Future<void> pickTime(bool start) async {
    final picked = await showWheelTimePicker(
      context: context,
      initialTime: start ? startTime : endTime,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        startTime = picked;
      } else {
        endTime = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = draft.until.isAfter(draft.from);
    return PanelContent(
      header: const PanelHeading(title: 'Custom timeline'),
      footer: PanelActions(
        children: [
          AppButton(
            label: 'Apply range',
            onPressed: valid ? () => Navigator.pop(context, draft) : null,
          ),
          AppButton(
            label: 'Cancel',
            secondary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('From date'),
            subtitle: Text(DateFormat.yMMMd().format(from)),
            trailing: const Icon(LucideIcons.calendar),
            onTap: withFeedback(() => pickDate(true)),
          ),
          ListTile(
            title: const Text('Through date'),
            subtitle: Text(DateFormat.yMMMd().format(through)),
            trailing: const Icon(LucideIcons.calendar),
            onTap: withFeedback(() => pickDate(false)),
          ),
          SwitchListTile(
            title: const Text('Set a time range'),
            subtitle: const Text(
              'Choose the start and end times within these dates',
            ),
            value: timed,
            onChanged: (value) {
              ActionFeedback.tap();
              setState(() => timed = value);
            },
          ),
          if (timed) ...[
            ListTile(
              title: const Text('Start time'),
              subtitle: Text(startTime.format(context)),
              trailing: const Icon(LucideIcons.clock3),
              onTap: withFeedback(() => pickTime(true)),
            ),
            ListTile(
              title: const Text('End time'),
              subtitle: Text(endTime.format(context)),
              trailing: const Icon(LucideIcons.clock3),
              onTap: withFeedback(() => pickTime(false)),
            ),
          ],
          if (!valid) const Text('Choose an end after the start.'),
        ],
      ),
    );
  }
}
