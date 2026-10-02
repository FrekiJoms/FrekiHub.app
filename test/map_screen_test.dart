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
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(bytes);
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
                body: MapScreen(data: data, tileProvider: _TestTiles()),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('2 logs'), findsOneWidget);
      await tester.tap(find.text('2 logs'));
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
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
