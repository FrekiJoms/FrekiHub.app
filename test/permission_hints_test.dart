import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freki_hub/data.dart';
import 'package:freki_hub/main.dart';
import 'package:freki_hub/startup.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/services.dart';

Future<BuildContext> mountHintHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late BuildContext host;
  await tester.pumpWidget(
    MaterialApp(
      theme: Design.theme(false),
      builder: (context, child) => KeyboardOverlay(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) {
          host = context;
          return const Scaffold(body: Text('Host'));
        },
      ),
    ),
  );
  return host;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
  );
  testWidgets(
    'Declining session notifications keeps running state cached and the record active',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final running = await db.clockIn('Running note');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        calls.add(call);
        if (call.method == 'cacheSession') return true;
        if (call.method == 'permissionStatus') return {'start': false};
        if (call.method == 'automationEvents') return '[]';
        return null;
      });
      const connectivity = MethodChannel(
        'dev.fluttercommunity.plus/connectivity',
      );
      const connectivityStatus = MethodChannel(
        'dev.fluttercommunity.plus/connectivity_status',
      );
      messenger.setMockMethodCallHandler(connectivity, (_) async => ['wifi']);
      messenger.setMockMethodCallHandler(connectivityStatus, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(connectivity, null);
        messenger.setMockMethodCallHandler(connectivityStatus, null);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dataProvider.overrideWith(
              (ref) => Stream.value(AppData([running], [], [], {})),
            ),
            graphicsProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: Design.theme(false),
            builder: (context, child) => KeyboardOverlay(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            ),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Keep your session in view'), findsOneWidget);
      final cached =
          calls.singleWhere((c) => c.method == 'cacheSession').arguments as Map;
      expect(cached['id'], running.id);
      expect(cached['note'], 'Running note');
      expect(calls.where((c) => c.method == 'start'), isEmpty);
      await tester.tap(find.text('Not now'));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await tester.runAsync(db.readAll))!.running?.id, running.id);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final entry in PermissionHints.specs.entries) {
    testWidgets(
      '${entry.key}: custom hint gates native access and can be declined',
      (tester) async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'permissionStatus') return {entry.key: false};
          return true;
        });
        final context = await mountHintHost(tester);
        final declined = PermissionHints.request<bool>(context, entry.key);
        await tester.pumpAndSettle();
        expect(find.text(entry.value.title), findsOneWidget);
        expect(find.text(entry.value.action).hitTestable(), findsOneWidget);
        expect(find.text('Not now').hitTestable(), findsOneWidget);
        expect(calls, ['permissionStatus']);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(await declined, isNull);
        expect(calls, ['permissionStatus']);
        final accepted = PermissionHints.request<bool>(context, entry.key);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.value.action));
        await tester.pumpAndSettle();
        expect(await accepted, true);
        expect(calls, ['permissionStatus', 'permissionStatus', entry.key]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Granted access skips the hint; explicit management still explains and opens settings',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        calls.add(call);
        return call.method == 'permissionStatus'
            ? {'receiptNotificationPermission': true}
            : true;
      });
      final context = await mountHintHost(tester);
      expect(
        await PermissionHints.request<bool>(
          context,
          'receiptNotificationPermission',
        ),
        true,
      );
      expect(find.byType(PermissionHint), findsNothing);
      final managed = PermissionHints.request<bool>(
        context,
        'receiptNotificationPermission',
        manage: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Access is already enabled.'), findsOneWidget);
      await tester.tap(find.text('Manage access'));
      await tester.pumpAndSettle();
      expect(await managed, true);
      expect(calls.last.method, 'permissionSettings');
      expect(calls.last.arguments, 'receiptNotificationPermission');
    },
  );

  testWidgets(
    'Concurrent requests do not stack hints; failure releases the gate',
    (tester) async {
      var allowed = false, fail = false, requests = 0;
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        if (call.method == 'permissionStatus') {
          requests++;
          return {'locationPermission': allowed};
        }
        if (fail) throw PlatformException(code: 'unavailable');
        return true;
      });
      final context = await mountHintHost(tester);
      final first = PermissionHints.request<bool>(
        context,
        'locationPermission',
      );
      await tester.pumpAndSettle();
      expect(
        await PermissionHints.request<bool>(context, 'locationPermission'),
        isNull,
      );
      expect(requests, 1);
      expect(find.byType(PermissionHint), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await first, isNull);
      allowed = true;
      fail = true;
      await expectLater(
        PermissionHints.request<bool>(context, 'locationPermission'),
        throwsA(isA<PlatformException>()),
      );
      fail = false;
      expect(
        await PermissionHints.request<bool>(context, 'locationPermission'),
        true,
      );
    },
  );
}
