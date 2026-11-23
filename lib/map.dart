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

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  final controller = MapController();
  final tileReset = StreamController<void>.broadcast();
  late final tileProvider =
      widget.tileProvider ??
      NetworkTileProvider(
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 32 * 1024 * 1024,
        ),
      );
  StreamSubscription<List<Map<String, dynamic>>>? subscription;
  Timer? contextTimer;
  Timer? locationExpiry;
  MapUserLocation? userLocation;
  bool locating = false, showUserLocation = true;
  static const userColor = Color(0xFF008CBA);
  static const clusterAmber = Color(0xFFD9822B);
  static const routeBlue = Color(0xFF3B6EF6);
  late final cameraMotion = AnimationController(vsync: this);
  static const locationHint = PermissionHintSpec(
    title: 'Find yourself on the map',
    intro: 'Show your current location and center the map on it.',
    benefit: 'A clear point of reference',
    detail: 'A pulsing circle marks your latest position. A soft halo shows its estimated accuracy.',
    control: 'This requests one location fix. It does not enable background tracking or add a saved log.',
    next: 'Choose Precise location and allow access while using the app.',
    action: 'Allow precise location',
    icon: LucideIcons.locateFixed,
  );

  static const _mutedTileMatrix = <double>[
    0.70, 0.32, 0.03, 0, 10, //
    0.10, 0.85, 0.03, 0, 10, //
    0.10, 0.32, 0.56, 0, 10, //
    0, 0, 0, 0.88, 0, //
  ];

  // Low-glare dark slate inversion for muted basemaps under dark Liquid Glass.
  static const _darkMutedTileMatrix = <double>[
    -0.18, -0.45, -0.09, 0, 206, //
    -0.23, -0.40, -0.09, 0, 208, //
    -0.23, -0.44, -0.03, 0, 212, //
    0, 0, 0, 0.92, 0, //
  ];

  Future<void> locateUser() async {
    if (locating || !ready) return;
    setState(() => locating = true);
    await guarded(context, () async {
      final allowed = await PermissionHints.request<bool>(
        context,
        'locationPermission',
        hint: locationHint,
      );
      if (!mounted || allowed == null) return;
      if (!allowed) {
        throw StateError('Allow precise location to find yourself on the map.');
      }
      String? raw;
      try {
        raw = await NativeSession.channel
            .invokeMethod<String>('mapCurrentLocation')
            .timeout(const Duration(seconds: 25));
      } on PlatformException catch (error) {
        throw StateError(
          error.message ?? 'Could not find your location. Enable precise location and try again.',
        );
      }
      if (!mounted) return;
      final fix = MapUserLocation.parse(raw, DateTime.now());
      if (fix == null) {
        throw StateError(
          'No fresh location fix yet. Check that Location is on and try again.',
        );
      }
      locationExpiry?.cancel();
      setState(() {
        userLocation = fix;
        showUserLocation = true;
      });
      locationExpiry = Timer(
        Duration(
          milliseconds: math.max(
            1,
            fix.sampled + 120000 - DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        () {
          if (!mounted) return;
          setState(() => userLocation = null);
          publishContext();
        },
      );
      panToUser(fix);
      publishContext();
    });
    if (mounted) setState(() => locating = false);
  }

  void panToUser(MapUserLocation fix) {
    final toZoom = fix.accuracy > 100
        ? math.max(2.0, 15 - math.log(fix.accuracy / 100) / math.ln2)
        : math.max(15.0, ready ? controller.camera.zoom : 15.0);
    panToPoint(LatLng(fix.lat, fix.lng), toZoom);
  }

  void panToPoint(LatLng target, double toZoom) {
    if (!ready) return;
    cameraMotion.stop();
    final from = controller.camera.center;
    final zoom = controller.camera.zoom;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.move(target, toZoom);
      return;
    }
    cameraMotion.duration = Motion.duration(context, 350);
    final deltaLng = (target.longitude - from.longitude + 540) % 360 - 180;
    void tick() {
      final t = Motion.curve.transform(cameraMotion.value);
      controller.move(
        LatLng(
          from.latitude + (target.latitude - from.latitude) * t,
          (from.longitude + deltaLng * t + 540) % 360 - 180,
        ),
        zoom + (toZoom - zoom) * t,
      );
    }

    cameraMotion.addListener(tick);
    cameraMotion
        .forward(from: 0)
        .orCancel
        .then((_) {}, onError: (Object _) {})
        .whenComplete(() => cameraMotion.removeListener(tick));
  }

  late String period = widget.data.prefs['mapPeriod'] ?? 'day';
  late DateTime date =
      DateTime.tryParse(widget.data.prefs['mapDate'] ?? '') ?? DateTime.now();
  late MapRange range = MapRange.period(period, date);
  late bool trace = widget.data.prefs['mapTrace'] == 'true';
  late bool mutedMap = widget.data.prefs['mapMuted'] == 'true';
  final categories = <String>{'Sessions', 'Finance', 'Locations', 'Other'};
  Set<String> selected = {};
  Set<String> inspectedIds = {};
  String? activeRouteId;
  List<MapRecord> records = [];
  List<Map<String, dynamic>> unlocated = [];
  List<Map<String, dynamic>> previousRows = [];
  int queryGeneration = 0;
  bool ready = false, loading = true, tileError = false;
  String? loadError;
  String lastContext = '';
  int clusterZoom = 2;
  bool clusterUpdateQueued = false;
  List<MapRecord>? clusteredRecords;
  String clusterSignature = '';
  List<List<MapRecord>> clusters = [];
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
              final recordIds = records.map((r) => r.id).toSet();
              selected.retainAll(recordIds);
              inspectedIds.retainAll(recordIds);
              loading = false;
              loadError = null;
            });
            publishContext();
            if (firstLoad &&
                ready &&
                visible.isNotEmpty &&
                userLocation == null) {
              fit();
            }
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
        'map.current_location_visible':
            userLocation != null && showUserLocation,
        'map.current_location_sample_epoch': userLocation?.sampled ?? 0,
        'map.current_location_accuracy': userLocation?.accuracy ?? 0,
        'map.period': period,
        'map.from': dayKey(range.from),
        'map.until': dayKey(range.until),
        'map.from_epoch': range.from.millisecondsSinceEpoch,
        'map.until_epoch': range.until.millisecondsSinceEpoch,
        'map.trace_enabled': trace,
        'map.muted': mutedMap,
        'map.visible_count': visible.length,
        'map.cluster_count': clusters.length,
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
      await db.pref('mapMuted', mutedMap);
    });
    publishContext();
  }

  void fit([List<MapRecord>? subset]) {
    cameraMotion.stop();
    final points = subset ?? traced;
    if (!ready || points.isEmpty) return;
    final coordinates = points.map((r) => LatLng(r.lat, r.lng)).toList();
    if (coordinates.every((p) => p == coordinates.first)) {
      controller.move(coordinates.first, 15);
    } else {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(coordinates),
          padding: EdgeInsets.fromLTRB(
            52,
            math.min(170, MediaQuery.sizeOf(context).height * .28),
            64,
            math.min(
              130 + MediaQuery.viewPaddingOf(context).bottom,
              MediaQuery.sizeOf(context).height * .32,
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
      inspectedIds.clear();
      activeRouteId = null;
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
      inspectedIds.clear();
      activeRouteId = null;
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
      inspectedIds.clear();
      activeRouteId = null;
      watch();
    });
    await guarded(context, saveView);
  }

  Future<void> openPeriodMenu(BuildContext anchor) async {
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
  }

  void clearTraceFocus() {
    if (selected.isEmpty && activeRouteId == null) return;
    setState(() {
      selected.clear();
      activeRouteId = null;
    });
    unawaited(guarded(context, saveView));
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
    setState(() {
      selected = result;
      if (selected.isNotEmpty) trace = true;
    });
    unawaited(guarded(context, saveView));
    if (selected.isNotEmpty) fit();
  }

  Future<void> openMapOptions() async {
    final now = DateTime.now();
    final isTodayView = period == 'day' && dayKey(date) == dayKey(now);
    final result = await panel<String>(
      context,
      _MapOptionsSheet(
        trace: trace,
        mutedMap: mutedMap,
        locatedCount: visible.length,
        unlocatedCount: unlocated.length,
        selectedCount: selected.length,
        showJumpToToday: !isTodayView,
        onTraceChanged: (value) {
          setState(() => trace = value);
          unawaited(guarded(context, saveView));
        },
        onMutedChanged: (value) {
          setState(() => mutedMap = value);
          unawaited(guarded(context, saveView));
        },
        onClearSelection: () {
          setState(() {
            selected.clear();
            activeRouteId = null;
          });
          unawaited(guarded(context, saveView));
        },
      ),
    );
    if (!mounted) return;
    if (result == 'logs') {
      await showRecords();
    } else if (result == 'today') {
      setState(() {
        period = 'day';
        date = DateTime.now();
        range = MapRange.period('day', date);
        selected.clear();
        inspectedIds.clear();
        activeRouteId = null;
        watch();
      });
      await guarded(context, saveView);
    }
  }

  Future<void> openLocationSheet(MapRecord record) async {
    setState(() => inspectedIds = {record.id});
    try {
      await panel<void>(
        context,
        _MapLocationSheet(
          record: record,
          isSelected: selected.contains(record.id),
          onToggleTrace: () {
            setState(() {
              if (!selected.remove(record.id)) {
                selected.add(record.id);
                trace = true;
              }
            });
            unawaited(guarded(context, saveView));
          },
          onCenter: () {
            panToPoint(
              LatLng(record.lat, record.lng),
              math.max(16.0, ready ? controller.camera.zoom : 16.0),
            );
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() => inspectedIds = {});
      }
    }
  }

  Future<void> openClusterSheet(List<MapRecord> items) async {
    setState(() => inspectedIds = items.map((r) => r.id).toSet());
    String? action;
    MapRecord? chosenRecord;
    try {
      final result = await panel<Object?>(
        context,
        _MapClusterSheet(
          records: items.reversed.toList(),
          selected: selected,
          onZoomToCluster: () {
            final center = clusterCenter(items);
            panToPoint(
              LatLng(center.lat, center.lng),
              math.min(18.0, (ready ? controller.camera.zoom : 12.0) + 2.0),
            );
          },
        ),
      );
      if (result is String) action = result;
      if (result is MapRecord) chosenRecord = result;
    } finally {
      if (mounted) {
        setState(() => inspectedIds = {});
      }
    }
    if (!mounted) return;
    if (action == 'view_all') {
      await showRecords(items);
    } else if (chosenRecord != null) {
      await openLocationSheet(chosenRecord);
    }
  }

  Future<void> openRouteSheet(MapRouteGroup routeGroup) async {
    setState(() => activeRouteId = routeGroup.id);
    String? action;
    MapRecord? chosenRecord;
    try {
      final result = await panel<Object?>(
        context,
        _MapRouteSheet(route: routeGroup),
      );
      if (result is String) action = result;
      if (result is MapRecord) chosenRecord = result;
    } finally {
      if (mounted) {
        setState(() => activeRouteId = null);
      }
    }
    if (!mounted) return;
    if (action == 'trace_route') {
      setState(() {
        selected = routeGroup.records.map((r) => r.id).toSet();
        trace = true;
      });
      unawaited(guarded(context, saveView));
      fit(routeGroup.records);
    } else if (chosenRecord != null) {
      await openLocationSheet(chosenRecord);
    }
  }

  ({List<MapRouteGroup> active, List<MapRouteGroup> historical}) _buildRoutes(
    List<MapRecord> shown,
    List<MapRecord> tracedRecords,
  ) {
    final allRoutes = splitMapRoutes(shown);
    if (!trace && selected.isEmpty && activeRouteId == null) {
      return (active: const [], historical: const []);
    }
    if (selected.isNotEmpty) {
      final active = tracedRecords.length > 1
          ? [MapRouteGroup(id: 'selected', records: tracedRecords)]
          : const <MapRouteGroup>[];
      final historical = trace
          ? allRoutes
                .where((g) => !g.records.every((r) => selected.contains(r.id)))
                .toList()
          : const <MapRouteGroup>[];
      return (active: active, historical: historical);
    }
    if (allRoutes.isEmpty) {
      return (active: const [], historical: const []);
    }
    final targetId = activeRouteId ?? allRoutes.last.id;
    final active = <MapRouteGroup>[];
    final historical = <MapRouteGroup>[];
    for (final route in allRoutes) {
      if (route.id == targetId) {
        active.add(route);
      } else {
        historical.add(route);
      }
    }
    if (active.isEmpty && allRoutes.isNotEmpty) {
      active.add(historical.removeLast());
    }
    return (active: active, historical: historical);
  }

  void _handleMapTap(LatLng tapPoint, List<MapRouteGroup> routes) {
    if (!ready || routes.isEmpty) return;
    final tapOffset = controller.camera.latLngToScreenOffset(tapPoint);
    MapRouteGroup? bestRoute;
    var bestDist = 22.0;
    for (final route in routes) {
      for (var i = 0; i < route.records.length - 1; i++) {
        final a = controller.camera.latLngToScreenOffset(
          LatLng(route.records[i].lat, route.records[i].lng),
        );
        final b = controller.camera.latLngToScreenOffset(
          LatLng(route.records[i + 1].lat, route.records[i + 1].lng),
        );
        final dist = _distanceToSegment(tapOffset, a, b);
        if (dist <= bestDist) {
          bestDist = dist;
          bestRoute = route;
        }
      }
    }
    if (bestRoute != null) {
      ActionFeedback.tap();
      unawaited(openRouteSheet(bestRoute));
    } else if (activeRouteId != null) {
      setState(() => activeRouteId = null);
    }
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq <= 0.0001) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(
      0.0,
      1.0,
    );
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  List<Widget> displayActions() => [
    if (tileError || loadError != null)
      control('Retry map loading', LucideIcons.refreshCw, retry),
    control(
      'Map options',
      LucideIcons.layers,
      () => openMapOptions(),
      active: trace || mutedMap || selected.isNotEmpty,
    ),
    control(
      'Center on current location',
      LucideIcons.locateFixed,
      () => locateUser(),
      enabled: ready && !locating,
      busy: locating,
    ),
    control(
      'Fit recorded locations',
      LucideIcons.scan,
      fit,
      enabled: ready && traced.isNotEmpty,
    ),
  ];

  Widget control(
    String label,
    IconData icon,
    VoidCallback action, {
    bool? active,
    bool enabled = true,
    bool busy = false,
  }) => IconButton(
    tooltip: label,
    isSelected: active,
    onPressed: withFeedback(enabled ? action : null),
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      maximumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
      backgroundColor: Colors.transparent,
      foregroundColor: active == true
          ? Theme.of(context).colorScheme.onSurface
          : null,
    ),
    icon: Container(
      key: active == null ? null : const ValueKey('map-toggle-indicator'),
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active == true
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .12)
            : Colors.transparent,
      ),
      child: SkeletonValue(
        loading: busy,
        semanticsLabel: 'Finding current location',
        child: Icon(icon, size: 18),
      ),
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
    final routeRecords = traced;
    final signature = '$clusterZoom:${categories.join(',')}';
    if (!identical(clusteredRecords, records) ||
        clusterSignature != signature) {
      clusteredRecords = records;
      clusterSignature = signature;
      clusters = clusterMapRecords(shown, clusterZoom);
    }
    final routeBundles = _buildRoutes(shown, routeRecords);
    final allDisplayedRoutes = [
      ...routeBundles.historical,
      ...routeBundles.active,
    ];
    final hasSelectionFocus =
        inspectedIds.isNotEmpty || selected.isNotEmpty || activeRouteId != null;
    final activeRouteRecordIds = {
      for (final g in routeBundles.active)
        if (activeRouteId != null || selected.isNotEmpty)
          ...g.records.map((r) => r.id),
    };
    final viewBottom = MediaQuery.viewPaddingOf(c).bottom;
    final scheme = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    final dateLabel = period == 'day'
        ? DateFormat('EEE, d MMM yyyy').format(range.from)
        : period == 'month'
        ? DateFormat('MMMM yyyy').format(range.from)
        : period == 'year'
        ? '${range.from.year}'
        : period == 'custom'
        ? '${DateFormat('d MMM yyyy, HH:mm').format(range.from)} – ${DateFormat('d MMM yyyy, HH:mm').format(range.until.subtract(const Duration(minutes: 1)))}'
        : '${DateFormat('d MMM').format(range.from)} – ${DateFormat('d MMM yyyy').format(range.until.subtract(const Duration(days: 1)))}';
    final counts = '${shown.length} located · ${unlocated.length} unlocated';
    final notice = widget.apiKey.trim().isEmpty
        ? 'Basemap not configured · saved dots remain'
        : tileError
        ? 'Basemap unavailable · saved dots remain'
        : loadError;
    final status = notice == null ? counts : '$counts · $notice';
    final tileLayer = widget.apiKey.trim().isNotEmpty
        ? TileLayer(
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
                WidgetsBinding.instance.ensureVisualUpdate();
              }
            },
          )
        : null;

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
                  onTap: (_, point) => _handleMapTap(point, allDisplayedRoutes),
                  onPositionChanged: (camera, gesture) {
                    if (gesture) cameraMotion.stop();
                    if (camera.zoom.floor() != clusterZoom &&
                        !clusterUpdateQueued) {
                      clusterUpdateQueued = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        clusterUpdateQueued = false;
                        if (mounted) {
                          setState(
                            () => clusterZoom = controller.camera.zoom.floor(),
                          );
                        }
                      });
                    }
                    publishContext();
                  },
                ),
                children: [
                  if (tileLayer != null)
                    mutedMap
                        ? ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              dark ? _darkMutedTileMatrix : _mutedTileMatrix,
                            ),
                            child: tileLayer,
                          )
                        : tileLayer,
                  if (allDisplayedRoutes.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        for (final route in routeBundles.historical)
                          Polyline(
                            points: route.records
                                .map((r) => LatLng(r.lat, r.lng))
                                .toList(),
                            color: routeBlue.withValues(alpha: .28),
                            strokeWidth: 2.5,
                          ),
                        for (final route in routeBundles.active) ...[
                          Polyline(
                            points: route.records
                                .map((r) => LatLng(r.lat, r.lng))
                                .toList(),
                            color: Colors.white.withValues(alpha: .78),
                            strokeWidth: 5.5,
                          ),
                          Polyline(
                            points: route.records
                                .map((r) => LatLng(r.lat, r.lng))
                                .toList(),
                            color: routeBlue,
                            strokeWidth: 3.2,
                          ),
                        ],
                      ],
                    ),
                  if (routeBundles.active.any((r) => r.records.length >= 2))
                    MarkerLayer(
                      markers: [
                        for (final route in routeBundles.active)
                          if (route.records.length >= 2) ...[
                            Marker(
                              point: LatLng(
                                route.records.first.lat,
                                route.records.first.lng,
                              ),
                              width: 24,
                              height: 24,
                              child: const IgnorePointer(
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF1F8A5B),
                                      border: Border.fromBorderSide(
                                        BorderSide(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: SizedBox(width: 11, height: 11),
                                  ),
                                ),
                              ),
                            ),
                            Marker(
                              point: LatLng(
                                route.records.last.lat,
                                route.records.last.lng,
                              ),
                              width: 24,
                              height: 24,
                              child: const IgnorePointer(
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: routeBlue,
                                      border: Border.fromBorderSide(
                                        BorderSide(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                      ),
                                    ),
                                    child: SizedBox(width: 12, height: 12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  MarkerLayer(
                    markers: clusters.map((items) {
                      final record = items.last;
                      final center = clusterCenter(items);
                      final isCluster = items.length > 1;
                      final highlighted = items.any(
                        (r) =>
                            inspectedIds.contains(r.id) ||
                            selected.contains(r.id) ||
                            activeRouteRecordIds.contains(r.id),
                      );
                      final dimmed = hasSelectionFocus && !highlighted;
                      final markerColor = isCluster
                          ? clusterAmber
                          : colors[record.category]!;
                      final markerSize = isCluster
                          ? (highlighted ? 38.0 : 32.0)
                          : (highlighted ? 22.0 : 15.0);
                      return Marker(
                        point: LatLng(center.lat, center.lng),
                        width: 48,
                        height: 48,
                        child: Semantics(
                          label: isCluster
                              ? 'Location cluster: ${items.length} records near ${record.location}'
                              : '${record.category}: ${record.title} at ${record.location}',
                          button: true,
                          selected: highlighted,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: withFeedback(
                              () => isCluster
                                  ? openClusterSheet(items)
                                  : openLocationSheet(items.single),
                            ),
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: dimmed ? .48 : 1.0,
                                duration: Motion.duration(c, 150),
                                child: AnimatedContainer(
                                  duration: Motion.duration(c, 160),
                                  curve: Motion.curve,
                                  width: highlighted
                                      ? markerSize + 10
                                      : markerSize,
                                  height: highlighted
                                      ? markerSize + 10
                                      : markerSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: highlighted
                                        ? markerColor.withValues(alpha: .24)
                                        : Colors.transparent,
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: markerSize,
                                      height: markerSize,
                                      decoration: BoxDecoration(
                                        color: markerColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: highlighted ? 3 : 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 5,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: isCluster
                                          ? Center(
                                              child: Text(
                                                items.length > 99
                                                    ? '99+'
                                                    : '${items.length}',
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: highlighted
                                                      ? 12
                                                      : 11,
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
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (userLocation != null && showUserLocation)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(userLocation!.lat, userLocation!.lng),
                          radius: userLocation!.accuracy,
                          useRadiusInMeter: true,
                          color: userColor.withValues(alpha: .10),
                          borderColor: userColor.withValues(alpha: .25),
                          borderStrokeWidth: 1,
                        ),
                      ],
                    ),
                  if (userLocation != null && showUserLocation)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(userLocation!.lat, userLocation!.lng),
                          width: 48,
                          height: 48,
                          child: Semantics(
                            label:
                                'Your current location, estimated accuracy ${userLocation!.accuracy.round()} meters',
                            child: const IgnorePointer(
                              child: LocationPulse(
                                key: ValueKey('map-user-location'),
                                color: userColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // LAYER 1: Top navigation (compact date/stats pill + floating segmented strip)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Builder(
                        builder: (anchor) => Semantics(
                          label: dateLabel,
                          hint: 'Long press to change timeline mode',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: withFeedback(
                              () => openPeriodMenu(anchor),
                            ),
                            child: Chrome(
                              key: const ValueKey('map-date-pill'),
                              borderRadius: 24,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              child: IntrinsicWidth(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Previous timeline',
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(24, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            disabledColor: scheme.onSurface
                                                .withValues(alpha: .3),
                                            onPressed: period == 'custom'
                                                ? null
                                                : withFeedback(() => shift(-1)),
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 24,
                                                  height: 28,
                                                ),
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                              LucideIcons.chevronLeft,
                                              size: 14,
                                            ),
                                          ),
                                          Expanded(
                                            child: Tooltip(
                                              message: 'Timeline mode',
                                              triggerMode:
                                                  TooltipTriggerMode.manual,
                                              child: InkWell(
                                                onTap: withFeedback(selectDate),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: AnimatedSwitcher(
                                                  duration: Motion.duration(
                                                    c,
                                                    200,
                                                  ),
                                                  transitionBuilder:
                                                      (
                                                        child,
                                                        animation,
                                                      ) => FadeTransition(
                                                        opacity: animation,
                                                        child: SlideTransition(
                                                          position:
                                                              Tween<Offset>(
                                                                begin: Offset(
                                                                  child.key ==
                                                                          ValueKey(
                                                                            '$period:${range.from}',
                                                                          )
                                                                      ? shiftDirection *
                                                                            .15
                                                                      : -shiftDirection *
                                                                            .15,
                                                                  0,
                                                                ),
                                                                end:
                                                                    Offset.zero,
                                                              ).animate(
                                                                CurvedAnimation(
                                                                  parent:
                                                                      animation,
                                                                  curve: Motion
                                                                      .curve,
                                                                ),
                                                              ),
                                                          child: child,
                                                        ),
                                                      ),
                                                  child: Text(
                                                    period == 'year'
                                                        ? '${date.year}'
                                                        : period == 'day'
                                                        ? DateFormat('d MMM')
                                                              .format(date)
                                                        : period == 'week'
                                                        ? DateFormat(
                                                            'd MMM',
                                                          ).format(range.from)
                                                        : period == 'custom'
                                                        ? 'Custom range'
                                                        : DateFormat.MMMM()
                                                              .format(date),
                                                    key: ValueKey(
                                                      '$period:${range.from}',
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Tooltip(
                                            message: 'Change timeline period',
                                            triggerMode:
                                                TooltipTriggerMode.manual,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: withFeedback(
                                                () => openPeriodMenu(anchor),
                                              ),
                                              child: SizedBox(
                                                width: 18,
                                                height: 28,
                                                child: Icon(
                                                  LucideIcons.chevronDown,
                                                  size: 11,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Next timeline',
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(24, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            disabledColor: scheme.onSurface
                                                .withValues(alpha: .3),
                                            onPressed: period == 'custom'
                                                ? null
                                                : withFeedback(() => shift(1)),
                                            constraints:
                                                const BoxConstraints.tightFor(
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
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: withFeedback(() => showRecords()),
                                      child: Semantics(
                                        button: true,
                                        hint: 'Open timeline logs',
                                        child: Opacity(
                                          opacity: .55,
                                          child: SkeletonValue(
                                            loading: loading,
                                            semanticsLabel:
                                                'Loading recorded locations',
                                            child: Text(
                                              status,
                                              key: const ValueKey(
                                                'map-record-counts',
                                              ),
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                height: 1.3,
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
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Chrome(
                      key: const ValueKey('map-legends'),
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
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
                            children: [
                              _MapSegmentItem(
                                label: 'You',
                                icon: LucideIcons.locateFixed,
                                color: userColor,
                                selected:
                                    userLocation != null && showUserLocation,
                                enabled: !locating,
                                onTap: () {
                                  ActionFeedback.tap();
                                  if (userLocation == null) {
                                    locateUser();
                                  } else {
                                    setState(
                                      () =>
                                          showUserLocation = !showUserLocation,
                                    );
                                    publishContext();
                                  }
                                },
                              ),
                              ...colors.entries.map(
                                (entry) => _MapSegmentItem(
                                  label: entry.key,
                                  icon: icons[entry.key]!,
                                  color: entry.value,
                                  selected: categories.contains(entry.key),
                                  onTap: () {
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selected.isNotEmpty || activeRouteId != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Chrome(
                        key: const ValueKey('map-trace-pill'),
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.route,
                              size: 13,
                              color: routeBlue,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                selected.isNotEmpty
                                    ? 'Tracing ${selected.length} ${selected.length == 1 ? 'stop' : 'stops'}'
                                    : 'Route focused',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Semantics(
                              button: true,
                              label: 'Clear trace selection',
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: withFeedback(clearTraceFocus),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 13,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // LAYER 3: Right-side floating map tools (two compact Liquid Glass groups)
            Positioned(
              top: 0,
              bottom: 0,
              right: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      96,
                      bounds.maxHeight - 280 - viewBottom,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chrome(
                          key: const ValueKey('map-tools-rail'),
                          borderRadius: 24,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: displayActions(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Chrome(
                          key: const ValueKey('map-zoom-rail'),
                          borderRadius: 24,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              control('Zoom in', LucideIcons.plus, () {
                                cameraMotion.stop();
                                controller.move(
                                  controller.camera.center,
                                  math.min(19, controller.camera.zoom + 1),
                                );
                              }, enabled: ready),
                              Container(
                                width: 22,
                                height: 1,
                                color: scheme.onSurface.withValues(alpha: .10),
                              ),
                              control('Zoom out', LucideIcons.minus, () {
                                cameraMotion.stop();
                                controller.move(
                                  controller.camera.center,
                                  math.max(2, controller.camera.zoom - 1),
                                );
                              }, enabled: ready),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // LAYER 4: Subtle unlocated-log action pill + attribution strip clear of PillNavigation
            if (!loading && shown.isEmpty && unlocated.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: viewBottom + 92,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Chrome(
                    key: const ValueKey('map-unlocated-pill'),
                    borderRadius: 14,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: withFeedback(() => showRecords()),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.listFilter,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${unlocated.length} unlocated ${unlocated.length == 1 ? 'log' : 'logs'} · Tap to view',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: viewBottom + 66,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: dark ? .52 : .64),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: dark ? .10 : .42),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      'Powered by Geoapify · © OpenStreetMap contributors',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface.withValues(alpha: .72),
                      ),
                    ),
                  ),
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
    locationExpiry?.cancel();
    cameraMotion.dispose();
    tileReset.close();
    controller.dispose();
    super.dispose();
  }
}

class _MapSegmentItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MapSegmentItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: AnimatedOpacity(
          opacity: selected ? 1.0 : .42,
          duration: Motion.duration(context, 150),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: Motion.duration(context, 150),
                curve: Motion.curve,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: selected
                      ? scheme.onSurface.withValues(alpha: .08)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapOptionsSheet extends StatefulWidget {
  final bool trace;
  final bool mutedMap;
  final int locatedCount;
  final int unlocatedCount;
  final int selectedCount;
  final bool showJumpToToday;
  final ValueChanged<bool> onTraceChanged;
  final ValueChanged<bool> onMutedChanged;
  final VoidCallback onClearSelection;

  const _MapOptionsSheet({
    required this.trace,
    required this.mutedMap,
    required this.locatedCount,
    required this.unlocatedCount,
    required this.selectedCount,
    this.showJumpToToday = false,
    required this.onTraceChanged,
    required this.onMutedChanged,
    required this.onClearSelection,
  });

  @override
  State<_MapOptionsSheet> createState() => _MapOptionsSheetState();
}

class _MapOptionsSheetState extends State<_MapOptionsSheet> {
  late bool trace = widget.trace;
  late bool mutedMap = widget.mutedMap;
  late int selectedCount = widget.selectedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PanelContent(
      header: const PanelHeading(
        title: 'Map options',
        leading: Chrome(
          borderRadius: 22,
          padding: EdgeInsets.all(10),
          child: Icon(LucideIcons.layers, size: 20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Show chronological trace'),
            subtitle: const Text('Connect recorded stops along routes'),
            value: trace,
            onChanged: (value) {
              ActionFeedback.tap();
              setState(() => trace = value);
              widget.onTraceChanged(value);
            },
          ),
          SwitchListTile(
            title: const Text('Muted map style'),
            subtitle: const Text(
              'Soften map contrast so routes and clusters stand out',
            ),
            value: mutedMap,
            onChanged: (value) {
              ActionFeedback.tap();
              setState(() => mutedMap = value);
              widget.onMutedChanged(value);
            },
          ),
          const Divider(height: 16),
          if (widget.showJumpToToday)
            ListTile(
              leading: const Icon(LucideIcons.calendarCheck2),
              title: const Text('Jump to today'),
              subtitle: const Text('Switch back to today’s day timeline'),
              trailing: Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: withFeedback(() => Navigator.pop(context, 'today')),
            ),
          ListTile(
            leading: const Icon(LucideIcons.listFilter),
            title: const Text('Timeline logs'),
            subtitle: Text(
              '${widget.locatedCount} located · ${widget.unlocatedCount} unlocated',
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            onTap: withFeedback(() => Navigator.pop(context, 'logs')),
          ),
          if (selectedCount > 0)
            ListTile(
              leading: Icon(
                LucideIcons.xCircle,
                color: scheme.onSurfaceVariant,
              ),
              title: Text('Clear trace selection ($selectedCount)'),
              onTap: withFeedback(() {
                setState(() => selectedCount = 0);
                widget.onClearSelection();
              }),
            ),
        ],
      ),
    );
  }
}

class _MapClusterSheet extends StatelessWidget {
  final List<MapRecord> records;
  final Set<String> selected;
  final VoidCallback onZoomToCluster;

  const _MapClusterSheet({
    required this.records,
    required this.selected,
    required this.onZoomToCluster,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final countLabel = records.length > 99 ? '99+' : '${records.length}';
    return PanelContent(
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _MapScreenState.clusterAmber,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    countLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location cluster',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${records.length} recorded locations',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: withFeedback(() {
                    Navigator.pop(context);
                    onZoomToCluster();
                  }),
                  child: const Text('Zoom in'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nearby records',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: withFeedback(
                    () => Navigator.pop(context, 'view_all'),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
          ],
        ),
      ),
      scrollable: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final record = records[index];
          final kind = record.details['kind']?.toString();
          final catColor = _MapScreenState.colors[record.category]!;
          final isTraced = selected.contains(record.id);
          return Surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: catColor,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(
                record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${DateFormat('d MMM · HH:mm').format(record.time)}'
                '${kind != null && kind.isNotEmpty ? ' · ($kind)' : ' · ${record.category}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTraced)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        LucideIcons.route,
                        size: 14,
                        color: _MapScreenState.routeBlue,
                      ),
                    ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              onTap: withFeedback(() => Navigator.pop(context, record)),
            ),
          );
        },
      ),
    );
  }
}

class _MapLocationSheet extends StatefulWidget {
  final MapRecord record;
  final bool isSelected;
  final VoidCallback onToggleTrace;
  final VoidCallback onCenter;

  const _MapLocationSheet({
    required this.record,
    required this.isSelected,
    required this.onToggleTrace,
    required this.onCenter,
  });

  @override
  State<_MapLocationSheet> createState() => _MapLocationSheetState();
}

class _MapLocationSheetState extends State<_MapLocationSheet> {
  late bool isSelected = widget.isSelected;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final scheme = Theme.of(context).colorScheme;
    final catColor = _MapScreenState.colors[record.category]!;
    final kind = record.details['kind']?.toString();
    final categoryTag = kind != null && kind.isNotEmpty
        ? kind
        : record.category;
    return PanelContent(
      header: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _MapScreenState.icons[record.category],
              size: 18,
              color: catColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('d MMM yyyy · HH:mm').format(record.time)} · ($categoryTag)',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: PanelActions(
        children: [
          AppButton(
            label: isSelected ? 'In trace' : 'Trace point',
            icon: LucideIcons.route,
            secondary: isSelected,
            onPressed: () {
              setState(() => isSelected = !isSelected);
              widget.onToggleTrace();
            },
          ),
          AppButton(
            label: 'Center map',
            icon: LucideIcons.crosshair,
            secondary: true,
            onPressed: () {
              Navigator.pop(context);
              widget.onCenter();
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.location,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  logDetails(record.row),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: LogDeleteButton(
              onDelete: () async {
                final db = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(databaseProvider);
                final deleted = await deleteActivityLog(context, db, record.id);
                if (deleted && context.mounted) {
                  Navigator.pop(context);
                }
                return deleted;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MapRouteSheet extends StatelessWidget {
  final MapRouteGroup route;

  const _MapRouteSheet({required this.route});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final span =
        '${DateFormat('d MMM · HH:mm').format(route.start)} – ${DateFormat('HH:mm').format(route.end)}';
    return PanelContent(
      header: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _MapScreenState.routeBlue.withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.route,
              size: 18,
              color: _MapScreenState.routeBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recorded route',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${route.records.length} stops · $span',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: withFeedback(
              () => Navigator.pop(context, 'trace_route'),
            ),
            child: const Text('Focus'),
          ),
        ],
      ),
      scrollable: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: route.records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final record = route.records[index];
          final catColor = _MapScreenState.colors[record.category]!;
          return Surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: catColor,
                  ),
                ),
              ),
              title: Text(
                record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${DateFormat('HH:mm').format(record.time)} · ${record.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              onTap: withFeedback(() => Navigator.pop(context, record)),
            ),
          );
        },
      ),
    );
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
  late final List<MapRecord> records = [...widget.records];
  late final List<Map<String, dynamic>> unlocated = [...widget.unlocated];
  Widget deleteAction(String id) => LogDeleteButton(
    onDelete: () async {
      final db = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(databaseProvider);
      final deleted = await deleteActivityLog(context, db, id);
      if (deleted && mounted) {
        setState(() {
          records.removeWhere((r) => r.id == id);
          unlocated.removeWhere((r) => r['id'] == id);
          selected.remove(id);
        });
      }
      return deleted;
    },
  );
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
                      () => selected.addAll(records.map((r) => r.id)),
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
      child: records.isEmpty && unlocated.isEmpty
          ? ListView(
              children: const [
                EmptyState(
                  'No records with a usable location',
                  'Locations recorded during this timeline will appear here.',
                  LucideIcons.mapPin,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: records.length + unlocated.length,
              itemBuilder: (c, i) {
                if (i >= records.length) {
                  final row = unlocated[i - records.length];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (i == records.length && records.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Text(
                            'UNLOCATED LOGS (${unlocated.length})',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(c).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LogRow(
                          key: ValueKey('map-log-${row['id']}'),
                          details: logDetails(row),
                          action: deleteAction(row['id'] as String),
                          title: row['title']?.toString() ?? 'Activity',
                          dateTime: DateFormat('d MMM yyyy, HH:mm:ss').format(
                            DateTime.fromMillisecondsSinceEpoch(
                              row['time'] as int,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                final record = records[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LogRow(
                    key: ValueKey('map-log-${record.id}'),
                    details: logDetails(record.row),
                    action: deleteAction(record.id),
                    title: record.title,
                    dateTime: DateFormat('d MMM yyyy, HH:mm:ss')
                        .format(record.time),
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
