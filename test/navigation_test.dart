import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/design.dart';

void main() {
  testWidgets(
    'Hold center, drag to expense, release selects; outside cancels',
    (tester) async {
      String? action;
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 400,
                child: PillNavigation(
                  index: 0,
                  onChanged: (value) => selected = value,
                  onQuickAdd: (value) => action = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(PillNavigation));
      await tester.tapAt(center - const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tapAt(center + const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(selected, 2);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Expense'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(find.text('Expense')));
      await tester.pump(const Duration(milliseconds: 160));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(action, 'expense');
      expect(find.text('Expense'), findsNothing);
      action = null;
      final cancel = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      await cancel.moveTo(const Offset(5, 5));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(action, isNull);
      expect(find.text('Expense'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
