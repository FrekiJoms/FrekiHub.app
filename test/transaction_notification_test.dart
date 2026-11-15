import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/automation_sync.dart';
import 'package:freki_hub/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Rule expenses, settings and top toasts reconcile once', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    bool acknowledged = false;
    const events = [
      {
        'id': 'rule:expense',
        'action': 'purchase',
        'time': 1790902800000,
        'amount': '99.50',
        'currency': 'PHP',
        'category': 'Food',
        'merchant': 'Lunch',
        'source': 'Automation',
      },
      {
        'id': 'rule:setting',
        'action': 'rule_setting',
        'time': 1790902800000,
        'title': 'Setting changed',
        'key': 'sound',
        'value': 'true',
      },
      {
        'id': 'rule:toast',
        'action': 'rule_toast',
        'time': 1790902800000,
        'title': 'Rule matched',
      },
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      if (call.method == 'automationEvents') {
        return jsonEncode(acknowledged ? [] : events);
      }
      if (call.method == 'automationAck') acknowledged = true;
      if (call.method == 'transactionSaved') return true;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
    );
    await AutomationSync.reconcile(db);
    final data = await db.readAll();
    expect(data.entries.single.category, 'Food');
    expect(data.entries.single.kind, 'expense');
    expect(data.entries.single.amount, 9950);
    expect(data.prefs['sound'], 'true');
    expect(data.prefs['ruleToast:rule:toast'], 'Rule matched');
    await AutomationSync.reconcile(db);
    expect((await db.readAll()).entries.length, 1);
  });
  test('Saved purchase receipts retry permission denial and do not repeat on replay', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var queued = true, allowed = false;
    final receipts = <Map<String, dynamic>>[];
    final savedCounts = <int>[];
    const event = {
      'id': 'purchase:ref123',
      'action': 'purchase',
      'time': 1790902800000,
      'amount': '1234.50',
      'currency': 'PHP',
      'merchant': 'Coffee shop',
      'source': 'Payment app',
      'package': 'payment.app',
      'location': 'Town',
      'reference': 'ref123',
      'title': 'Purchased at Coffee shop',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeSession.channel, (call) async {
          switch (call.method) {
            case 'automationEvents':
              return jsonEncode(queued ? [event] : []);
            case 'pending':
              return null;
            case 'automationAck':
              queued = false;
              return null;
            case 'automationConfig':
              return null;
            case 'transactionSaved':
              savedCounts.add((await db.readAll()).entries.length);
              if (allowed) {
                receipts.add(Map<String, dynamic>.from(call.arguments as Map));
              }
              return allowed;
            default:
              throw StateError('Unexpected ${call.method}');
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSession.channel, null),
    );
    await AutomationSync.reconcile(db);
    expect(receipts, isEmpty);
    expect(
      (await db.readPreferences()).keys.any(
        (k) => k.startsWith('purchaseNotice:'),
      ),
      isTrue,
    );
    allowed = true;
    await AutomationSync.reconcile(db);
    expect(receipts.single['title'], 'Transaction saved');
    expect(receipts.single['amount'], '₱1,234.50');
    expect(receipts.single['merchant'], 'Coffee shop');
    expect(receipts.single['reference'], 'ref123');
    expect(savedCounts, [1, 1]);
    expect(
      (await db.readPreferences()).keys.any(
        (k) => k.startsWith('purchaseNotice:'),
      ),
      isFalse,
    );
    queued = true;
    await AutomationSync.reconcile(db);
    expect(receipts.length, 1);
    expect((await db.readAll()).entries.length, 1);
  });

  test(
    'Detected income imports as Finance income and confirms after commit',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var queued = true;
      final receipts = <Map<String, dynamic>>[];
      const event = {
        'id': 'income:wallet.app:ref-income-123',
        'action': 'purchase',
        'kind': 'income',
        'time': 1790902800000,
        'amount': '2500.00',
        'currency': 'PHP',
        'merchant': 'Ana',
        'source': 'Wallet app',
        'package': 'wallet.app',
        'reference': 'ref-income-123',
        'title': 'Received income · Ana',
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSession.channel, (call) async {
            switch (call.method) {
              case 'automationEvents':
                return jsonEncode(queued ? [event] : []);
              case 'pending':
                return null;
              case 'automationAck':
                queued = false;
                return null;
              case 'automationConfig':
                return null;
              case 'transactionSaved':
                expect((await db.readAll()).entries.single.kind, 'income');
                receipts.add(Map<String, dynamic>.from(call.arguments as Map));
                return true;
              default:
                throw StateError('Unexpected ${call.method}');
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeSession.channel, null),
      );

      await AutomationSync.reconcile(db);

      final data = await db.readAll();
      expect(data.entries.single.kind, 'income');
      expect(data.entries.single.amount, 250000);
      expect(data.entries.single.note, 'Ana');
      expect(receipts.single['kind'], 'income');
      expect(receipts.single['merchant'], 'Ana');
      await AutomationSync.reconcile(db);
      expect((await db.readAll()).entries.length, 1);
      expect(receipts.length, 1);
    },
  );

  test('Rolled-back purchase never confirms or acknowledges a save', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.readAll();
    await db.customStatement(
      "CREATE TRIGGER reject_receipt BEFORE INSERT ON preferences WHEN NEW.key LIKE 'purchaseNotice:%' BEGIN SELECT RAISE(ABORT, 'simulated save failure'); END",
    );
    var notices = 0, acknowledgements = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeSession.channel, (call) async {
          switch (call.method) {
            case 'automationEvents':
              return jsonEncode([
                {
                  'id': 'purchase:failed',
                  'action': 'purchase',
                  'time': 1790902800000,
                  'amount': '10.00',
                  'currency': 'PHP',
                  'merchant': 'Shop',
                  'source': 'Payment app',
                },
              ]);
            case 'pending':
              return null;
            case 'transactionSaved':
              notices++;
              return true;
            case 'automationAck':
              acknowledgements++;
              return null;
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSession.channel, null),
    );
    await expectLater(AutomationSync.reconcile(db), throwsA(isA<Exception>()));
    expect((await db.readAll()).entries, isEmpty);
    expect(notices, 0);
    expect(acknowledgements, 0);
  });

  test(
    'Reconciliation invokes smsScan only when smsScanning is enabled',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var smsScans = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        switch (call.method) {
          case 'smsScan':
            smsScans++;
            return 0;
          case 'automationEvents':
            return '[]';
          case 'pending':
          case 'automationConfig':
            return null;
          default:
            return null;
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
      );

      await AutomationSync.reconcile(db);
      expect(smsScans, 0);

      await db.pref('smsScanning', false);
      await AutomationSync.reconcile(db);
      expect(smsScans, 0);

      await db.pref('smsScanning', true);
      await AutomationSync.reconcile(db);
      expect(smsScans, 1);
    },
  );

  test('Reconciliation invokes smsScan only when smsScanning is enabled', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var smsScans = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      switch (call.method) {
        case 'smsScan':
          smsScans++;
          return 0;
        case 'automationEvents':
          return '[]';
        case 'pending':
        case 'automationConfig':
          return null;
        default:
          return null;
      }
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
    );

    await AutomationSync.reconcile(db);
    expect(smsScans, 0);

    await db.pref('smsScanning', false);
    await AutomationSync.reconcile(db);
    expect(smsScans, 0);

    await db.pref('smsScanning', true);
    await AutomationSync.reconcile(db);
    expect(smsScans, 1);
  });
}
