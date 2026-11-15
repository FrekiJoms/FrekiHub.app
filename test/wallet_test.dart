import 'dart:async';
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
    expect(WalletSkin.byName('Maya').id, 'maya');
    expect(WalletSkin.byName('MariBank').id, 'maribank');
    expect(WalletSkin.byName('SeaBank').id, 'maribank');
    expect(WalletSkin.byName('GoTyme').id, 'gotyme');
    expect(WalletSkin.byName('HelloMoney').id, 'hellomoney');
    expect(WalletSkin.byName('BPI Savings').id, 'bpi');
    expect(WalletSkin.byName('UnionBank').id, 'unionbank');
    expect(WalletSkin.byName('Something new').id, 'ink');
    expect(WalletSkin.resolve('GCash', 'bdo').id, 'bdo');
    expect(WalletSkin.resolve('GoTyme', 'gotyme_fifa').id, 'gotyme_fifa');
    expect(WalletSkin.resolve('GCash', 'custom').id, 'gcash');
    expect(WalletSkin.resolve('GCash', 'unknown').id, 'gcash');
    expect(WalletSkin.byId('maya').assetPath, 'assets/wallet-cards/maya.png');
    expect(
      WalletSkin.byId('gotyme_fifa').assetPath,
      'assets/wallet-cards/gotyme_fifa.png',
    );
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
      {
        'methods': jsonEncode(['Cash', 'GCash']),
      },
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
      {
        'methods': jsonEncode(['Cash', 'GCash']),
      },
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
    final accounts = walletAccounts(scopedData, [
      'GCash',
      'Cash',
    ], walletCommitments(planned));
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

    await tester.ensureVisible(find.text('Savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();
    expect(find.text('SAVED · GCASH'), findsOneWidget);
    expect(find.textContaining('from this wallet'), findsOneWidget);
    Navigator.of(tester.element(find.text('SAVED · GCASH'))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    final planSheet = find.byType(PanelContent);
    expect(find.text('Plan · GCash'), findsOneWidget);
    expect(
      find.descendant(of: planSheet, matching: find.text('Rent')),
      findsOneWidget,
    );
    expect(find.text('Allowance'), findsNothing);
    Navigator.of(tester.element(find.text('Plan · GCash'))).pop();
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
    final gcashCard = find.byWidgetPredicate(
      (w) => w is WalletCard && w.account.name == 'GCash',
    );
    expect(gcashCard, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(gcashCard),
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
    expect(
      find.byWidgetPredicate((w) => w is WalletCard && w.account.name == 'Maya'),
      findsOneWidget,
    );
  });

  testWidgets(
    'wallet stack peeks cards behind, supports bidirectional swipe in PageView, and preserves vertical scroll',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() => db.readAll());
      final data = AppData(const [], const [], const [], {
        'methods': jsonEncode(['GCash', 'Maya', 'BPI', 'Cash']),
        'walletOrder': jsonEncode(['GCash', 'Maya', 'BPI', 'Cash']),
        'walletView': 'stack',
      });
      final pageController = PageController(initialPage: 1);
      final scrollController = ScrollController();
      addTearDown(pageController.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Scaffold(
              body: PageView(
                controller: pageController,
                children: [
                  const SizedBox.expand(),
                  Center(
                    child: SizedBox(
                      width: 360,
                      height: 640,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            WalletSection(data: data),
                            const SizedBox(height: 600),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Rect rectFor(String name) => tester.getRect(
        find.byWidgetPredicate((w) => w is WalletCard && w.account.name == name),
      );

      final gcashRect = rectFor('GCash');
      final mayaRect = rectFor('Maya');
      final bpiRect = rectFor('BPI');
      final cashRect = rectFor('Cash');

      // Each card behind peeks cleanly above the card in front and tapers slightly.
      expect(gcashRect.top, greaterThan(mayaRect.top));
      expect(mayaRect.top, greaterThan(bpiRect.top));
      expect(bpiRect.top, greaterThan(cashRect.top));
      expect(gcashRect.width, greaterThan(mayaRect.width));
      expect(mayaRect.width, greaterThan(bpiRect.width));
      expect(bpiRect.width, greaterThan(cashRect.width));

      // Vertical drag on the front card scrolls the page without reordering.
      await tester.dragFrom(gcashRect.center, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(40));
      expect(pageController.page, 1.0);
      scrollController.jumpTo(0);
      await tester.pumpAndSettle();

      // Swiping left advances to Maya without switching PageView tab.
      await tester.dragFrom(rectFor('GCash').center, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(pageController.page, 1.0);

      var saved = await tester.runAsync(() => db.readAll());
      expect(
        jsonDecode(saved!.prefs['walletOrder']!),
        ['Maya', 'BPI', 'Cash', 'GCash'],
      );

      // Swiping right returns GCash to the front without switching PageView tab.
      await tester.dragFrom(rectFor('Maya').center, const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(pageController.page, 1.0);

      saved = await tester.runAsync(() => db.readAll());
      expect(
        jsonDecode(saved!.prefs['walletOrder']!),
        ['GCash', 'Maya', 'BPI', 'Cash'],
      );
    },
  );

  testWidgets('wallet stack buttons and reduced motion reorder cleanly', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() => db.readAll());
    final data = AppData(const [], const [], const [], {
      'methods': jsonEncode(['GCash', 'Maya', 'BPI']),
      'walletOrder': jsonEncode(['GCash', 'Maya', 'BPI']),
      'walletView': 'stack',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next wallet'));
    await tester.pumpAndSettle();
    var saved = await tester.runAsync(() => db.readAll());
    expect(jsonDecode(saved!.prefs['walletOrder']!), ['Maya', 'BPI', 'GCash']);

    await tester.tap(find.byTooltip('Previous wallet'));
    await tester.pumpAndSettle();
    saved = await tester.runAsync(() => db.readAll());
    expect(jsonDecode(saved!.prefs['walletOrder']!), ['GCash', 'Maya', 'BPI']);
  });

  testWidgets(
    'live flow: add wallet, add expense, scope total & month cards, edit design, and remove wallet stay synced',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final controller = StreamController<AppData>.broadcast();
      final today = dayKey(DateTime.now());
      Future<AppData> emitLatest() async {
        final d = await db.readAll();
        if (!controller.isClosed) controller.add(d);
        return d;
      }

      final initial = await tester.runAsync(() async {
        await db.pref('methods', jsonEncode(['Cash', 'GCash']));
        await db
            .into(db.entries)
            .insert(dated('seed-inc', today, 'income', 100000, 'GCash'));
        return db.readAll();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWith((ref) => controller.stream),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final d = ref.watch(dataProvider).value ?? initial!;
                  return BudgetScreen(data: d);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Total balance and Month net start synchronized for all wallets.
      expect(find.text('TOTAL BALANCE'), findsWidgets);
      expect(find.text('MONTH NET · ALL WALLETS'), findsOneWidget);
      expect(find.text('₱1,000.00'), findsWidgets);

      // 2. Add a new wallet/payment method from Finance "+" button.
      await tester.ensureVisible(find.byTooltip('Add wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add wallet'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Add wallet'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add wallet'));
      await tester.pumpAndSettle();

      var latest = await tester.runAsync(emitLatest);
      await tester.pumpAndSettle();
      expect(latest!.methods, contains('Maya'));
      expect(latest.walletMethods, contains('Maya'));

      // 3. Add an expense to Maya via DB and verify both Total Balance and Month Net update immediately.
      latest = await tester.runAsync(() async {
        await db
            .into(db.entries)
            .insert(dated('maya-exp', today, 'expense', 25000, 'Maya'));
        return emitLatest();
      });
      await tester.pumpAndSettle();
      expect(find.text('₱750.00'), findsWidgets);

      // 4. Scope Finance to Maya and verify BOTH Total Balance and Month Net cards scope to Maya.
      await tester.ensureVisible(find.text('All wallets').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All wallets').first);
      await tester.pumpAndSettle();
      final mayaChoice = find.text('Maya').last;
      await tester.ensureVisible(mayaChoice);
      await tester.pumpAndSettle();
      await tester.tap(mayaChoice);
      await tester.pumpAndSettle();

      expect(find.text('WALLET BALANCE · MAYA'), findsOneWidget);
      expect(find.text('MONTH NET · MAYA'), findsOneWidget);
      expect(find.text(money(-25000, 'PHP')), findsWidgets);

      // 5. Card design preference updates immediately via dataProvider.
      latest = await tester.runAsync(() async {
        await db.pref('wallet:Maya:style', 'ink');
        return emitLatest();
      });
      await tester.pumpAndSettle();
      expect(
        walletAccounts(latest!).firstWhere((a) => a.name == 'Maya').skin.id,
        'ink',
      );

      // 6. Removing Maya from Wallets/Payment methods updates both lists.
      latest = await tester.runAsync(() async {
        final d = await db.readAll();
        await db.pref(
          'methods',
          jsonEncode(d.methods.where((m) => m != 'Maya').toList()),
        );
        await db.pref(
          'hiddenWallets',
          jsonEncode([...d.hiddenWallets, 'maya']),
        );
        await db.pref(
          'walletOrder',
          jsonEncode(walletStoredOrder(d.prefs)..remove('Maya')),
        );
        return emitLatest();
      });
      await tester.pumpAndSettle();
      expect(latest!.methods, isNot(contains('Maya')));
      expect(latest.walletMethods, isNot(contains('Maya')));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await controller.close();
        await db.close();
      });
    },
  );

  test(
    'transfers move balances between wallets without affecting monthly income/expenses',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final today = dayKey(DateTime.now());
        await db.pref('methods', jsonEncode(['GCash', 'Cash']));
        await db
            .into(db.entries)
            .insert(dated('inc', today, 'income', 100000, 'GCash'));
        await db.saveTransfer(
          day: today,
          amount: 35000,
          currency: 'PHP',
          fromMethod: 'GCash',
          toMethod: 'Cash',
          note: 'ATM cash out',
        );
        final data = await db.readAll();
        expect(data.walletBalance('GCash'), 65000);
        expect(data.walletBalance('Cash'), 35000);

        final month = financeMonth(
          data,
          DateTime.now(),
          null,
          const [],
        );
        expect(month.income, 100000);
        expect(month.expenses, 0);
        expect(month.net, 100000);

        final pairKey = data.entries
            .firstWhere((e) => e.kind == 'transfer_out')
            .occurrence!;
        await db.deleteTransfer(pairKey);
        final afterDelete = await db.readAll();
        expect(afterDelete.walletBalance('GCash'), 100000);
        expect(afterDelete.walletBalance('Cash'), 0);
      } finally {
        await db.close();
      }
    },
  );

  testWidgets('WalletTransferSheet swaps wallets and saves atomic transfer', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final today = dayKey(DateTime.now());
    final initial = await tester.runAsync(() async {
      await db.pref('methods', jsonEncode(['GCash', 'Cash']));
      await db
          .into(db.entries)
          .insert(dated('inc', today, 'income', 50000, 'GCash'));
      return db.readAll();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: Design.theme(false),
          home: Scaffold(
            body: WalletTransferSheet(
              data: initial!,
              initialFrom: 'GCash',
              initialTo: 'Cash',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Swap From/To and swap back so both start/end states are exercised.
    await tester.tap(find.byTooltip('Swap wallets'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Swap wallets'));
    await tester.pumpAndSettle();

    // Use quick-fill chip "50%" -> 250.00 from GCash (500.00) to Cash.
    await tester.tap(find.text('50%'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Transfer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => db.readAll());
    expect(saved!.walletBalance('GCash'), 25000);
    expect(saved.walletBalance('Cash'), 25000);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => db.close());
  });
}
