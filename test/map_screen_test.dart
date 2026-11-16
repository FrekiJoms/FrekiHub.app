import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freki_hub/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

class _TestTiles extends TileProvider {
  int requests = 0;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return MemoryImage(bytes);
  }
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'User location is opt-in, centers, toggles and expires (reduced: $reduced)',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final data = (await tester.runAsync(db.readAll))!;
        final calls = <MethodCall>[];
        final accuracy = reduced ? 115.2 : 10.0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
          calls.add(call);
          if (call.method == 'permissionStatus') {
            return {'locationPermission': true};
          }
          if (call.method == 'locationPermission') return true;
          if (call.method == 'mapCurrentLocation') {
            return jsonEncode({
              'lat': 14.5,
              'lng': 121,
              'accuracy': accuracy,
              'locationTime': DateTime.now().millisecondsSinceEpoch,
            });
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: Design.theme(false),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: child!,
              ),
              home: Scaffold(
                body: MapScreen(
                  data: data,
                  tileProvider: _TestTiles(),
                  apiKey: 'test-key',
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(calls.where((c) => c.method == 'mapCurrentLocation'), isEmpty);
        expect(find.text('You'), findsOneWidget);
        await tester.tap(find.byTooltip('Center on current location'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();
        final camera = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        expect(camera.center.latitude, closeTo(14.5, .001));
        expect(camera.center.longitude, closeTo(121, .001));
        expect(camera.zoom, reduced ? lessThan(15) : 15);
        expect(
          tester
              .widget<CircleLayer>(find.byType(CircleLayer))
              .circles
              .single
              .radius,
          accuracy,
        );
        expect(find.byKey(const ValueKey('map-user-location')), findsOneWidget);
        await tester.tap(find.text('You'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('map-user-location')), findsNothing);
        await tester.tap(find.text('You'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('map-user-location')), findsOneWidget);
        expect(
          calls.where((c) => c.method == 'mapCurrentLocation'),
          hasLength(1),
        );
        await tester.pump(const Duration(minutes: 2, seconds: 1));
        await tester.pump();
        expect(find.byKey(const ValueKey('map-user-location')), findsNothing);
        expect(
          (await tester.runAsync(db.readAll))!.prefs['locationEnabled'],
          isNull,
        );
        expect(
          await tester.runAsync(
            () => db.customSelect('SELECT * FROM activity_logs').get(),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
  testWidgets('Map location hint cancellation never requests GPS', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final data = (await tester.runAsync(db.readAll))!;
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      calls.add(call);
      if (call.method == 'permissionStatus') {
        return {'locationPermission': false};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: MapScreen(
              data: data,
              tileProvider: _TestTiles(),
              apiKey: 'test-key',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Center on current location'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Find yourself on the map'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PermissionHint), findsNothing);
    expect(
      calls.where(
        (c) => ['locationPermission', 'mapCurrentLocation'].contains(c.method),
      ),
      isEmpty,
    );
    expect(find.byKey(const ValueKey('map-user-location')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'Inline timeline modes navigate directly and custom disables arrows',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(db.readAll);
      final data = AppData([], [], [], {
        'mapDate': '2026-10-04',
        'mapPeriod': 'month',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Scaffold(
              body: MapScreen(
                data: data,
                tileProvider: _TestTiles(),
                apiKey: 'test-key',
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widgetList<SkeletonValue>(find.byType(SkeletonValue))
            .where((value) => value.loading)
            .length,
        1,
      );
      expect(find.text('Loading recorded locations…'), findsNothing);
      expect(
        find.ancestor(
          of: find.text('October'),
          matching: find.byType(SkeletonValue),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('October'), findsOneWidget);
      expect(
        tester
            .widgetList<SkeletonValue>(find.byType(SkeletonValue))
            .every((value) => !value.loading),
        isTrue,
      );
      expect(find.text('By month'), findsNothing);
      final pillWidth = tester
          .getSize(find.byKey(const ValueKey('map-date-pill')))
          .width;
      expect(pillWidth, lessThan(656));
      final pillRect = tester.getRect(
        find.byKey(const ValueKey('map-date-pill')),
      );
      expect(
        tester.getRect(find.byTooltip('Previous timeline')).left -
            pillRect.left,
        closeTo(10.8, 0.05),
      );
      expect(
        pillRect.right - tester.getRect(find.byTooltip('Next timeline')).right,
        closeTo(10.8, 0.05),
      );
      expect(find.text('Month'), findsNothing);

      await tester.tap(find.byTooltip('Timeline mode'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next timeline'));
      await tester.pumpAndSettle();
      expect(find.text('November'), findsOneWidget);
      expect(find.text('Timeline'), findsNothing);
      await tester.tap(find.byTooltip('Previous timeline'));
      await tester.pumpAndSettle();
      await tester.longPress(find.byTooltip('Timeline mode'));
      await tester.pumpAndSettle();
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next timeline'));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);
      await tester.tap(find.byTooltip('Change timeline period'));
      await tester.pumpAndSettle();
      expect(find.text('Week'), findsOneWidget);
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      for (final mode in ['Week', 'Day']) {
        await tester.longPress(find.byTooltip('Timeline mode'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        final heading = find.descendant(
          of: find.byType(AnimatedSwitcher),
          matching: find.byType(Text),
        );
        final before = tester.widget<Text>(heading).data;
        await tester.tap(find.byTooltip('Next timeline'));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(heading).data, isNot(before));
        await tester.tap(find.byTooltip('Previous timeline'));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(heading).data, before);
      }

      await tester.longPress(find.byTooltip('Timeline mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.text('Custom timeline'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Start time'), findsOneWidget);
      expect(find.text('End time'), findsOneWidget);
      await tester.tap(find.text('Apply range'));
      await tester.pumpAndSettle();
      for (final label in ['Previous timeline', 'Next timeline']) {
        final button = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label,
          ),
        );
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets('Missing map key preserves records without requesting tiles', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final data = (await tester.runAsync(db.readAll))!;
    final tiles = _TestTiles();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: MapScreen(data: data, tileProvider: tiles, apiKey: '  '),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(TileLayer), findsNothing);
    expect(tiles.requests, 0);
    expect(
      find.textContaining('Basemap not configured · saved dots remain'),
      findsOneWidget,
    );
    expect(find.byTooltip('Map options'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
    'Late locations fit the camera and unlocated logs stay readable',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final data = (await tester.runAsync(db.readAll))!;
      final tiles = _TestTiles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Scaffold(
              body: MapScreen(
                data: data,
                tileProvider: tiles,
                apiKey: 'test-key',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        layer.urlTemplate,
        startsWith('https://maps.geoapify.com/v1/tile/osm-carto/'),
      );
      expect(layer.urlTemplate, endsWith('?apiKey=test-key'));
      expect(
        find.text('Powered by Geoapify · © OpenStreetMap contributors'),
        findsOneWidget,
      );
      final camera = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(camera.camera.center.latitude, 0);
      final time = DateTime.now().millisecondsSinceEpoch;
      final writes = (() async {
        await db.addActivity({
          'id': 'late',
          'time': time,
          'action': 'location',
          'title': 'Late recorded sample',
          'location': 'Place',
          'lat': 14.5,
          'lng': 121,
          'locationTime': time,
        });
        await db.addActivity({
          'id': 'missing',
          'time': time,
          'action': 'clock_in',
          'title': 'Saved without GPS',
          'location': 'Location unavailable',
        });
        await db.addActivity({
          'id': 'stale',
          'time': time,
          'action': 'location',
          'title': 'Old cached sample',
          'location': 'Place',
          'lat': 15,
          'lng': 120,
          'locationTime': time - 120001,
        });
      })();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await writes;
      await tester.pump(const Duration(milliseconds: 600));
      expect(camera.camera.center.latitude, 14.5);
      expect(camera.camera.center.longitude, 121);
      expect(find.text('1 located · 2 unlocated'), findsOneWidget);
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Timeline logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
      await tester.pumpAndSettle();
      expect(find.text('Saved without GPS'), findsOneWidget);
      expect(find.text('Old cached sample'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      addTearDown(db.close);
    },
  );

  testWidgets(
    'Map keeps filters usable on narrow screens and selects grouped located logs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final tiles = _TestTiles();
      addTearDown(db.close);
      final time = DateTime.now().millisecondsSinceEpoch;
      final data = (await tester.runAsync(() async {
        await db.addActivity({
          'id': 'a',
          'time': time,
          'action': 'purchase',
          'title': 'Purchased lunch',
          'location': 'Cafe',
          'lat': 14.5,
          'lng': 121.0,
          'locationTime': time,
        });
        await db.addActivity({
          'id': 'b',
          'time': time,
          'action': 'clock_in',
          'title': 'Clocked in',
          'location': 'Cafe',
          'lat': 14.5,
          'lng': 121.0,
          'locationTime': time,
        });
        return db.readAll();
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(true),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: MapScreen(
                  data: data,
                  tileProvider: tiles,
                  apiKey: 'test-key',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('2 located · 0 unlocated'), findsOneWidget);
      final counts = find.byKey(const ValueKey('map-record-counts'));
      final datePill = find.byKey(const ValueKey('map-date-pill'));
      expect(find.descendant(of: datePill, matching: counts), findsOneWidget);
      expect(
        tester.getRect(counts).top,
        greaterThan(tester.getRect(find.byTooltip('Timeline mode')).bottom),
      );
      expect(
        tester.getRect(counts).bottom,
        lessThan(tester.getRect(datePill).bottom),
      );
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: counts, matching: find.byType(Opacity)).first,
            )
            .opacity,
        .55,
      );

      expect(
        tester.getRect(find.byTooltip('Previous timeline')).top,
        closeTo(19.8, 0.05),
      );
      expect(tester.getRect(find.byTooltip('Zoom in')).height, 44);
      final toolsRail = tester.getRect(
        find.byKey(const ValueKey('map-tools-rail')),
      );
      final zoomRail = tester.getRect(
        find.byKey(const ValueKey('map-zoom-rail')),
      );
      expect(toolsRail.right, 308);
      expect(zoomRail.right, 308);
      expect(zoomRail.top, greaterThanOrEqualTo(toolsRail.bottom + 10));
      expect(
        tester.getRect(find.byTooltip('Fit recorded locations')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Zoom in')).top),
      );
      final legends = find.byKey(const ValueKey('map-legends'));
      expect(
        tester.getRect(legends).top,
        greaterThanOrEqualTo(tester.getRect(datePill).bottom + 7),
      );
      expect(find.text('MAP'), findsNothing);
      expect(tester.getRect(legends).height, lessThanOrEqualTo(42));
      expect(
        find.descendant(of: legends, matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
      await tester.drag(
        find.descendant(
          of: legends,
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Other').hitTestable(), findsOneWidget);
      final otherFade = find.ancestor(
        of: find.text('Other'),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(otherFade).opacity, 1);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(otherFade).opacity, .42);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(otherFade).opacity, 1);
      final camera = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final zoom = camera.camera.zoom;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(camera.camera.zoom, zoom + 1);

      // Tapping the numbered amber cluster opens the contextual cluster sheet.
      final clusterTap = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('2'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(clusterTap.behavior, HitTestBehavior.opaque);
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('Location cluster'), findsOneWidget);
      expect(find.text('2 recorded locations'), findsOneWidget);
      expect(find.text('View all'), findsOneWidget);
      await tester.tap(find.text('Purchased lunch'));
      await tester.pumpAndSettle();
      expect(find.text('Trace point'), findsOneWidget);
      expect(find.text('Center map'), findsOneWidget);
      await tester.tap(find.text('Trace point'));
      await tester.pumpAndSettle();
      expect(find.text('In trace'), findsOneWidget);
      Navigator.of(tester.element(find.text('In trace'))).pop();
      await tester.pumpAndSettle();

      // Open Map options and verify trace/muted switches + Timeline logs.
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();
      expect(find.text('Map options'), findsOneWidget);
      expect(find.text('Show chronological trace'), findsOneWidget);
      expect(find.text('Muted map style'), findsOneWidget);
      await tester.tap(find.text('Muted map style'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorFiltered), findsWidgets);
      await tester.tap(find.text('Timeline logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
      await tester.pumpAndSettle();
      expect(find.text('Purchased lunch'), findsOneWidget);
      expect(find.text('Clocked in'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('2 located · 0 unlocated'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-trace-pill')), findsOneWidget);
      expect(find.text('Tracing 1 stop'), findsOneWidget);
      final optionsButton = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Map options',
        ),
      );
      expect(optionsButton.isSelected, isTrue);
      expect(optionsButton.style!.shape!.resolve({}), isA<CircleBorder>());
      final indicator = find.byKey(const ValueKey('map-toggle-indicator'));
      expect(tester.getSize(indicator), const Size(38, 38));
      final indicatorDecoration =
          tester.widget<Container>(indicator).decoration! as BoxDecoration;
      expect(indicatorDecoration.color!.a, closeTo(.12, .001));
      expect(tester.takeException(), isNull);
      final tile = TileImage(
        vsync: tester,
        coordinates: const TileCoordinates(0, 0, 0),
        imageProvider: MemoryImage(tiles.bytes),
        onLoadComplete: (_) {},
        onLoadError: (_, _, _) {},
        tileDisplay: TileDisplay.instantaneous(),
        errorImage: null,
        cancelLoading: Completer<void>(),
      );
      addTearDown(tile.dispose);
      tester.view.physicalSize = const Size(640, 720);
      await tester.pumpAndSettle();
      final beforeNotice = tester.getRect(datePill);
      final beforeLegendTop = tester.getRect(legends).top;
      tester.widget<TileLayer>(find.byType(TileLayer)).errorTileCallback!(
        tile,
        StateError('Offline'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Retry map loading'), findsOneWidget);
      final withNotice = tester.getRect(datePill);
      expect(withNotice.width, greaterThan(beforeNotice.width));
      expect(withNotice.height, beforeNotice.height);
      expect(withNotice.top, beforeNotice.top);
      expect(withNotice.width, lessThanOrEqualTo(640 - 144));
      expect(tester.getRect(legends).top, beforeLegendTop);
      final statusText = tester.widget<Text>(counts);
      expect(statusText.maxLines, 1);
      expect(statusText.softWrap, isFalse);
      expect(statusText.overflow, TextOverflow.ellipsis);

      final requests = tiles.requests;
      await tester.tap(find.byTooltip('Retry map loading'));
      await tester.pumpAndSettle();
      expect(tiles.requests, greaterThan(requests));
      expect(find.byTooltip('Retry map loading'), findsNothing);
      expect(find.text('2 located · 0 unlocated'), findsOneWidget);
      tester.view.physicalSize = const Size(640, 360);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byTooltip('Previous timeline')).top,
        closeTo(19.8, 0.05),
      );
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Timeline logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Timeline logs'));
      await tester.pumpAndSettle();
      expect(find.text('Timeline logs'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(640, 720);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Timeline logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchased lunch'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete log'));
      await tester.tap(find.text('Delete log'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Purchased lunch'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Log deleted'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1 located · 0 unlocated'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear trace selection'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-trace-pill')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('Unlocated-only map surfaces direct timeline logs shortcut', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final time = DateTime.now().millisecondsSinceEpoch;
    final data = (await tester.runAsync(() async {
      await db.addActivity({
        'id': 'u1',
        'time': time,
        'action': 'clock_in',
        'title': 'Office check-in',
        'location': 'Location unavailable',
      });
      return db.readAll();
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: MapScreen(
              data: data,
              tileProvider: _TestTiles(),
              apiKey: 'test-key',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('map-unlocated-pill')), findsOneWidget);
    expect(find.text('1 unlocated log · Tap to view'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-unlocated-pill')));
    await tester.pumpAndSettle();
    expect(find.text('Timeline logs'), findsOneWidget);
    expect(find.text('Office check-in'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
