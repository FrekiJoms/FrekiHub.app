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

    await tester.drag(find.text('GCASH'), const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final saved = await tester.runAsync(() => db.readAll());
    expect(jsonDecode(saved!.prefs['walletOrder']!), ['Maya', 'GCash']);
    expect(find.text('MAYA'), findsOneWidget);
  });
}
