import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/screens.dart';

Entry movement(
  String id,
  String kind,
  int amount,
  String method, {
  String currency = 'PHP',
}) => Entry(
  id: id,
  day: '2026-11-0${id.length}',
  kind: kind,
  amount: amount,
  currency: currency,
  category: 'Other',
  method: method,
  note: '',
);

Entry dated(
  String id,
  String day,
  String kind,
  int amount,
  String method, {
  String currency = 'PHP',
  String category = 'Other',
}) => Entry(
  id: id,
  day: day,
  kind: kind,
  amount: amount,
  currency: currency,
  category: category,
  method: method,
  note: '',
);

void main() {
  final entries = [
    movement('a', 'income', 100000, 'GCash'),
    movement('bb', 'expense', 25000, 'GCash'),
    movement('ccc', 'savings', 10000, 'GCash'),
    movement('dddd', 'expense', 5000, 'Cash'),
    movement('eeeee', 'expense', 1000, ''),
    movement('ffffff', 'income', 99900, 'GCash', currency: 'USD'),
  ];
  final data = AppData(const [], entries, const [], {
    'methods': jsonEncode(['Cash', 'GCash', 'Maya']),
  });

  test('wallet balances separate methods and add up to the ledger balance', () {
    final balances = data.walletBalances;
    expect(balances['GCash'], 65000);
    expect(balances['Cash'], -6000);
    expect(balances['Maya'], 0);
    expect(balances.values.fold(0, (sum, value) => sum + value), data.balance);
    expect(data.walletBalance('GCash'), 65000);
  });

  test('wallets ignore other currencies and normalize blank methods', () {
    expect(data.walletMethods, contains('GCash'));
    expect(data.walletMethods, isNot(contains('USD')));
    expect(data.walletEntries('GCash').map((entry) => entry.currency).toSet(), {
      'PHP',
    });
    expect(data.walletEntries('Cash').length, 2);
  });

  test('stored order is kept and new wallets follow by balance', () {
    expect(data.orderedWalletNames(['Maya', 'GCash']), [
      'Maya',
      'GCash',
      'Cash',
    ]);
    expect(data.orderedWalletNames(['Gone', 'Cash', 'Cash']), [
      'Cash',
      'GCash',
      'Maya',
    ]);
  });

  test('stored order parsing tolerates missing or malformed values', () {
    expect(walletStoredOrder(const {}), isEmpty);
    expect(walletStoredOrder({'walletOrder': 'not json'}), isEmpty);
    expect(
      walletStoredOrder({
        'walletOrder': jsonEncode(['GCash', 4, null, 'Cash']),
      }),
      ['GCash', 'Cash'],
    );
  });

  test('card artwork follows the method name unless a preset is stored', () {
    expect(WalletSkin.byName('GCash').id, 'gcash');
    expect(WalletSkin.byName('BPI Savings').id, 'bpi');
    expect(WalletSkin.byName('UnionBank').id, 'unionbank');
    expect(WalletSkin.byName('Something new').id, 'ink');
    expect(WalletSkin.resolve('GCash', 'bdo').id, 'bdo');
    expect(WalletSkin.resolve('GCash', 'custom').id, 'gcash');
    expect(WalletSkin.resolve('GCash', 'unknown').id, 'gcash');
  });

  test('wallet accounts use saved include and custom image preferences', () {
    final accounts = walletAccounts(
      AppData(const [], entries, const [], {
        'methods': jsonEncode(['Cash', 'GCash']),
        'wallet:Cash:include': 'false',
        'wallet:Cash:style': 'custom',
        'wallet:Cash:image': 'wallet-cards/missing.jpg',
      }),
    );
    final cash = accounts.firstWhere((account) => account.name == 'Cash');
    expect(cash.included, isFalse);
    expect(cash.imagePath, 'wallet-cards/missing.jpg');
    expect(cash.movements, 2);
    final gcash = accounts.firstWhere((account) => account.name == 'GCash');
    expect(gcash.included, isTrue);
    expect(gcash.imagePath, isNull);
    expect(gcash.skin.id, 'gcash');
  });

  test('masked amount never exposes digits', () {
    expect(walletMaskedAmount('PHP'), '₱••••••');
    expect(walletMaskedAmount('USD'), r'$••••••');
  });

  test('backups keep card design but not device image paths', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.pref('wallet:GCash:style', 'custom');
    await db.pref('wallet:GCash:image', 'C:/device/card.jpg');
    final backup = jsonDecode(await db.backup()) as Map<String, dynamic>;
    final prefs = Map<String, String>.from(backup['preferences'] as Map);
    expect(prefs['wallet:GCash:style'], 'custom');
    expect(prefs.containsKey('wallet:GCash:image'), isFalse);
    expect(walletImagePreference('wallet:BPI:image'), isTrue);
    expect(walletImagePreference('wallet:BPI:style'), isFalse);
  });

  test('lifetime savings and month rows can be scoped to one wallet', () {
    final scopedData = AppData(
      const [],
      [
        dated('i', '2030-01-01', 'income', 100000, 'GCash'),
        dated('e', '2030-01-02', 'expense', 25000, 'GCash'),
        dated('s', '2030-01-03', 'savings', 10000, 'GCash'),
        dated('c', '2030-01-04', 'expense', 6000, 'Cash'),
        dated('f', '2030-02-01', 'expense', 9999, 'GCash'),
      ],
      const [],
      {'methods': jsonEncode(['Cash', 'GCash'])},
    );
    expect(scopedData.savingsByWallet, {'GCash': 10000});
    expect(
      scopedData
          .scopedEntries(wallet: 'Cash', month: '2030-01')
          .map((entry) => entry.id),
      ['c'],
    );
    expect(scopedData.scopedEntries(month: '2030-01').length, 4);
    expect(scopedData.scopedEntries(wallet: 'GCash').length, 4);
  });

  test('finance month scopes totals, safe to spend and card commitments', () {
    final scopedData = AppData(
      const [],
      [
        dated('i', '2030-01-01', 'income', 100000, 'GCash'),
        dated('e', '2030-01-02', 'expense', 25000, 'GCash'),
        dated('s', '2030-01-03', 'savings', 10000, 'GCash'),
        dated('c', '2030-01-04', 'expense', 6000, 'Cash'),
        dated('f', '2030-02-01', 'expense', 9999, 'GCash'),
      ],
      [
        Rule(
          id: 'rent',
          title: 'Rent',
          kind: 'expense',
          amount: 20000,
          currency: 'PHP',
          quantity: 1,
          basis: 'fixed',
          cadence: 'monthly',
          start: '2030-01-31',
          category: 'Other',
          method: 'GCash',
          position: 0,
        ),
        Rule(
          id: 'goal',
          title: 'Goal',
          kind: 'savings',
          amount: 7000,
          currency: 'PHP',
          quantity: 1,
          basis: 'fixed',
          cadence: 'monthly',
          start: '2030-01-15',
          category: 'Other',
          method: 'Cash',
          position: 1,
        ),
      ],
      {'methods': jsonEncode(['Cash', 'GCash'])},
    );
    final period = DateTime(2030, 1);
    final planned = project(scopedData, period, DateTime(2030, 1, 31));

    final all = financeMonth(scopedData, period, null, planned);
    expect(all.income, 100000);
    expect(all.expenses, 31000);
    expect(all.savings, 10000);
    expect(all.net, 59000);
    expect(all.commitments, 27000);
    expect(all.safe, 32000);

    final gcash = financeMonth(
      scopedData,
      period,
      'GCash',
      planned.where((p) => p.rule.method == 'GCash').toList(),
    );
    expect(gcash.income, 100000);
    expect(gcash.expenses, 25000);
    expect(gcash.savings, 10000);
    expect(gcash.net, 65000);
    expect(gcash.commitments, 20000);
    expect(gcash.safe, 45000);

    expect(walletCommitments(planned), {'GCash': 20000, 'Cash': 7000});
    final accounts = walletAccounts(
      scopedData,
      ['GCash', 'Cash'],
      walletCommitments(planned),
    );
    expect(accounts.first.committed, 20000);
    expect(accounts.last.committed, 7000);
  });

  testWidgets('month card scope picker narrows Finance to one wallet', (
    tester,
  ) async {
    String? picked;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final data = AppData(const [], const [], const [], {
      'methods': jsonEncode(['Cash', 'GCash']),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: WalletSection(
                data: data,
                month: FinanceMonth(
                  period: DateTime(2026, 11),
                  income: 0,
                  expenses: 0,
                  savings: 0,
                  net: 0,
                  safe: 0,
                  commitments: 0,
                  used: 0,
                ),
                onWallet: (value) => picked = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('MONTH NET · ALL WALLETS'), findsOneWidget);
    await tester.tap(find.text('All wallets'));
    await tester.pumpAndSettle();
    expect(find.text('Finance scope'), findsOneWidget);
    final gcash = find.text('GCash');
    await tester.ensureVisible(gcash);
    await tester.pumpAndSettle();
    await tester.tap(gcash);
    await tester.pumpAndSettle();
    expect(picked, 'GCash');
  });

  testWidgets('Finance scope narrows the month, planner and savings goal', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final today = dayKey(DateTime.now());
    final data = AppData(
      const [],
      [
        dated('i', today, 'income', 100000, 'GCash'),
        dated('e', today, 'expense', 25000, 'GCash', category: 'Food'),
        dated('c', today, 'expense', 6000, 'Cash', category: 'Travel'),
        dated('s', today, 'savings', 10000, 'GCash'),
      ],
      [
        Rule(
          id: 'rent',
          title: 'Rent',
          kind: 'expense',
          amount: 20000,
          currency: 'PHP',
          quantity: 1,
          basis: 'fixed',
          cadence: 'monthly',
          start: today,
          category: 'Housing',
          method: 'GCash',
          position: 0,
        ),
        Rule(
          id: 'allowance',
          title: 'Allowance',
          kind: 'expense',
          amount: 7000,
          currency: 'PHP',
          quantity: 1,
          basis: 'fixed',
          cadence: 'monthly',
          start: today,
          category: 'Other',
          method: 'Cash',
          position: 1,
        ),
      ],
      {
        'methods': jsonEncode(['Cash', 'GCash']),
        'savingsGoal:PHP': '50000',
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataProvider.overrideWith((ref) => Stream.value(data)),
        ],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(body: BudgetScreen(data: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('MONTH NET · ALL WALLETS'), findsOneWidget);

    await tester.tap(find.text('All wallets'));
    await tester.pumpAndSettle();
    final gcash = find.text('GCash');
    await tester.ensureVisible(gcash);
    await tester.pumpAndSettle();
    await tester.tap(gcash);
    await tester.pumpAndSettle();

    expect(find.text('MONTH NET · GCASH'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('SAVED · GCASH'), 300);
    expect(find.textContaining('from this wallet'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Plan for GCash.'), 300);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Allowance'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('swiping the stack moves the front card back and persists it', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() => db.readAll());
    final data = AppData(const [], const [], const [], {
      'methods': jsonEncode(['GCash', 'Maya']),
      'walletView': 'stack',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: WalletSection(data: data),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GCASH'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('GCASH')),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final saved = await tester.runAsync(() => db.readAll());
    expect(jsonDecode(saved!.prefs['walletOrder']!), ['Maya', 'GCash']);
    expect(find.text('MAYA'), findsOneWidget);
  });
}
