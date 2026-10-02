import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

class _TestTiles extends TileProvider {
  int requests = 0;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return MemoryImage(bytes);
  }
}

void main() {
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
                body: MapScreen(data: data, tileProvider: tiles),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('2 logs'), findsOneWidget);
      final camera = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final zoom = camera.camera.zoom;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(camera.camera.zoom, zoom + 1);
      await tester.tap(find.text('2 logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-drag-handle')));
      await tester.pumpAndSettle();
      expect(find.text('Purchased lunch'), findsOneWidget);
      expect(find.text('Clocked in'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Trace selected logs, or all logs'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 samples · straight-line trace'), findsOneWidget);
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
      tester.widget<TileLayer>(find.byType(TileLayer)).errorTileCallback!(
        tile,
        StateError('Offline'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Retry map loading'), findsOneWidget);
      final requests = tiles.requests;
      await tester.tap(find.byTooltip('Retry map loading'));
      await tester.pumpAndSettle();
      expect(tiles.requests, greaterThan(requests));
      expect(find.byTooltip('Retry map loading'), findsNothing);
      expect(find.text('1 samples · straight-line trace'), findsOneWidget);
      tester.view.physicalSize = const Size(640, 360);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byTooltip('Previous timeline')).bottom,
        lessThan(tester.getRect(find.byTooltip('Fit recorded locations')).top),
      );
      expect(
        tester.getRect(find.byTooltip('Fit recorded locations')).bottom,
        lessThan(tester.getRect(find.text('Sessions')).top),
      );
      await tester.tap(find.byTooltip('Choose located logs'));
      await tester.pumpAndSettle();
      expect(find.text('Located logs'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
