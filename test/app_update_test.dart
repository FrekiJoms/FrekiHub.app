import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freki_hub/app_update.dart';
import 'package:freki_hub/design.dart';
import 'package:freki_hub/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolveUri expands GitHub shorthand and rejects non-HTTPS URLs', () {
    expect(
      AppUpdater.resolveUri('FrekiJoms/frxnance-releases').toString(),
      'https://api.github.com/repos/FrekiJoms/frxnance-releases/releases/latest',
    );
    expect(
      AppUpdater.resolveUri('https://github.com/FrekiJoms/frxnance-releases')
          .toString(),
      'https://api.github.com/repos/FrekiJoms/frxnance-releases/releases/latest',
    );
    expect(
      AppUpdater.resolveUri('https://example.com/version.json').toString(),
      'https://example.com/version.json',
    );
    expect(AppUpdater.resolveUri('http://example.com/version.json'), isNull);
    expect(AppUpdater.resolveUri(''), isNull);
  });

  test(
    'AppUpdateInfo.parse supports custom version.json and GitHub Releases',
    () {
      final custom = AppUpdateInfo.parse({
        'versionCode': 4,
        'versionName': '1.2.0',
        'apkUrl': 'https://example.com/app.apk',
        'notes': 'Bug fixes',
      });
      expect(custom, isNotNull);
      expect(custom!.versionCode, 4);
      expect(custom.versionName, '1.2.0');
      expect(custom.apkUrl, 'https://example.com/app.apk');
      expect(custom.notes, 'Bug fixes');

      final gh = AppUpdateInfo.parse({
        'tag_name': 'v1.0.2+3',
        'body': 'Added wallet polish',
        'assets': [
          {
            'name': 'app-debug.apk',
            'browser_download_url': 'https://github.com/FrekiJoms/releases/download/v1.0.2+3/app-debug.apk',
          },
        ],
      });
      expect(gh, isNotNull);
      expect(gh!.versionCode, 3);
      expect(gh.versionName, '1.0.2');
      expect(gh.notes, 'Added wallet polish');
      expect(gh.apkUrl, endsWith('app-debug.apk'));

      expect(
        AppUpdateInfo.parse({
          'versionCode': 2,
          'apkUrl': 'http://insecure.example.com/app.apk',
        }),
        isNull,
      );
      expect(
        AppUpdateInfo.parse({
          'versionCode': 0,
          'apkUrl': 'https://example.com/app.apk',
        }),
        isNull,
      );
    },
  );

  testWidgets(
    'showUpdateSheet opens modal and triggers installUpdate when allowed',
    (tester) async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'permissionStatus') {
          return {'installPackagesPermission': true};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: Design.theme(false),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => AppUpdater.showUpdateSheet(
                  context,
                  const AppUpdateInfo(
                    versionCode: 2,
                    versionName: '1.0.1',
                    apkUrl: 'https://example.com/app.apk',
                    notes: 'Faster sync',
                  ),
                  current: const AppVersionInfo(
                    versionName: '1.0.0',
                    versionCode: 1,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Version 1.0.1 (2)'), findsOneWidget);
      expect(find.text('Installed: 1.0.0 (1)'), findsOneWidget);
      expect(find.text('Faster sync'), findsOneWidget);

      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(calls, containsAll(['permissionStatus', 'installUpdate']));

      await messenger.handlePlatformMessage(
        NativeSession.channel.name,
        NativeSession.channel.codec.encodeMethodCall(
          const MethodCall('updateProgress', {
            'received': 50,
            'total': 100,
            'progress': 0.5,
          }),
        ),
        (_) {},
      );
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Downloading update… (50%)'), findsOneWidget);

      await messenger.handlePlatformMessage(
        NativeSession.channel.name,
        NativeSession.channel.codec.encodeMethodCall(
          const MethodCall('updateStatus', {'status': 'cancelled'}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Update was not installed.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('declining install permission hint keeps update sheet idle', (
    tester,
  ) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeSession.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'permissionStatus') {
        return {'installPackagesPermission': false};
      }
      return false;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeSession.channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: Design.theme(false),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppUpdater.showUpdateSheet(
                context,
                const AppUpdateInfo(
                  versionCode: 2,
                  versionName: '1.0.1',
                  apkUrl: 'https://example.com/app.apk',
                ),
                current: const AppVersionInfo(
                  versionName: '1.0.0',
                  versionCode: 1,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Install app updates'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(calls, ['permissionStatus', 'permissionStatus']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('showUpdateSheet renders Markdown release notes cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Design.theme(false),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppUpdater.showUpdateSheet(
                context,
                const AppUpdateInfo(
                  versionCode: 3,
                  versionName: '1.5.6',
                  apkUrl: 'https://example.com/app-release.apk',
                  notes:
                      "## What's Changed\n"
                      '- **Faster** sync for `app_release_v1.apk`\n'
                      '1. Fixed [notes](https://example.com/notes)\n'
                      '> Restart optional',
                ),
                current: const AppVersionInfo(
                  versionName: '1.5.5',
                  versionCode: 2,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text("What's Changed"), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(
      find.textContaining('Faster sync for app_release_v1.apk'),
      findsOneWidget,
    );
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('`'), findsNothing);
    expect(find.textContaining('Fixed notes'), findsOneWidget);
    expect(find.textContaining('https://example.com/notes'), findsNothing);
    expect(find.text('Restart optional'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
