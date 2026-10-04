import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'Log details expand separately from trace selection (reduced: $reduced)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = false;
        final details = logDetails({
          'action': 'purchase',
          'location': 'Cafe',
          'details': jsonEncode({
            'amount': 12345,
            'currency': 'PHP',
            'note': 'Lunch note',
            'position': jsonEncode({'lat': 14.5, 'lng': 121, 'accuracy': 10}),
          }),
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: Design.theme(false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduced,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  StatefulBuilder(
                    builder: (context, change) => LogRow(
                      key: const ValueKey('located'),
                      title: 'Purchased lunch',
                      dateTime: '5 Oct 2026, 12:00:00',
                      details: details,
                      leading: Checkbox(
                        value: selected,
                        onChanged: (value) => change(() => selected = value!),
                      ),
                    ),
                  ),
                  LogRow(
                    key: const ValueKey('unlocated'),
                    title: 'Saved without GPS',
                    dateTime: '5 Oct 2026, 13:00:00',
                    details: logDetails({
                      'action': 'clock_in',
                      'location': 'Location unavailable',
                      'details': '{}',
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.textContaining('Coordinates:'), findsNothing);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        expect(find.textContaining('Coordinates:'), findsNothing);
        await tester.tap(find.text('Purchased lunch'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Coordinates: 14.5, 121'), findsOneWidget);
        expect(find.textContaining('Note: Lunch note'), findsOneWidget);
        expect(find.textContaining('Amount:'), findsOneWidget);
        await tester.tap(find.text('Purchased lunch'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Coordinates:'), findsNothing);
        await tester.tap(find.text('Saved without GPS'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Location: Location unavailable'),
          findsOneWidget,
        );
        expect(selected, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('Missing or malformed optional metadata still opens safely', () {
    expect(
      logDetails({'action': 'clock_in', 'details': 'invalid'}),
      contains('Location: Not recorded'),
    );
    expect(
      logDetails({
        'details': jsonEncode({
          'amount': 'unclear',
          'currency': 'UNKNOWN',
          'custom': 'Extra information',
        }),
      }),
      contains('custom: Extra information'),
    );
  });
}
