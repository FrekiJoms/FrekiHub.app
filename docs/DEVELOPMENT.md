# FrekiHub development and verification

Read [Agent instructions](../AGENTS.md) first. This is an Android-first Flutter workspace; source knowledge and local tests do not replace device verification.

## Toolchain and installation

The checked-in Dart constraint is `^3.13.4`; use a compatible Flutter SDK and Java 17. Android compile/target SDK versions are resolved by the Flutter Gradle plugin. The minimum is explicitly API 35 (Android 15), required by HyperIsland ToolKit 0.4.0; devices below Android 15 cannot install this configuration. Dependencies are declared in `pubspec.yaml` with resolved versions in `pubspec.lock`; native dependencies include Play services location 21.4.0 and HyperIsland ToolKit 0.4.0.

From the project root, verify tooling and restore dependencies:

```powershell
flutter --version
flutter doctor -v
flutter pub get
```

Local host paths observed for this workspace, not portable requirements:

| Tool | Path |
| --- | --- |
| Flutter | `C:/Users/ranbing143/develop/flutter/bin/flutter.bat` |
| Dart | `C:/Users/ranbing143/develop/flutter/bin/cache/dart-sdk/bin/dart.exe` |
| JDK 17 | `C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot` |
| Android SDK | `C:/Users/ranbing143/AppData/Local/Android/Sdk` |

Do not reinstall a working toolchain or copy these user-specific paths into app runtime code. For the current managed environment, shell commands that start compiler processes may need the existing sandbox escalation workflow; that is unrelated to app permission prompts.

## Quick verification

Format affected Dart files, run static analysis, then the relevant existing tests. A whole-app audit can use the full suite once; minor documentation changes do not require repeated app test runs.

```powershell
dart format lib/CHANGED_FILE.dart
flutter analyze
flutter test --reporter expanded
git diff --check
```

`CHANGED_FILE.dart` is a placeholder for the actual edited file. In the current Windows environment, workspace-local temporary paths have helped compiler/JVM startup:

```powershell
New-Item -ItemType Directory -Path .tmp -Force | Out-Null
$env:TEMP = Join-Path $PWD '.tmp'
$env:TMP = $env:TEMP
flutter analyze
```

## Test routing

| Change | Relevant existing checks |
| --- | --- |
| Startup/readiness/reactive cache | `test/startup_test.dart` |
| Today clock/reduced motion/resume/time changes | `test/today_clock_test.dart` (painted hands, second boundaries, date rollover, backward time adjustment, elapsed time and live-time captions) |
| Home clock-out confirmation | `test/home_session_confirmation_test.dart` (compact actions, live duration, note prefill/editing, cancel/Back discarding edits, confirmation, repeated activation and both motion settings) |
| Shared adaptive drawers/components | `test/sheets_test.dart` (content fit, 70% expansion, dismissal, fixed slots, lazy lists and content changes); `test/layout_test.dart` (opening frames, nested selector/date picker, keyboard and cancellation) |
| Date/time wheel current-value action | `test/pickers_test.dart` (animated/reduced-motion jumps, selected wheel positions, Confirm gating, date bounds, leap-day correction and cancellation) |
| Bottom-bar gestures/keyboard position | `test/navigation_test.dart` (quick add, stable safe-inset position, keyboard opening/closing with unchanged page/input geometry and cached height-only layout with width/theme refresh) |
| Shared log rows/deletion | `test/log_rows_test.dart` (narrow enlarged text, expand/collapse in both motion settings, independent checkbox selection, unlocated and malformed metadata); `test/log_deletion_test.dart` (confirmation/cancel/error feedback, atomic deletion, stream/observable updates, source-record preservation and replay/backup protection) |
| Foreground Map location | `test/map_screen_test.dart` (opt-in GPS, contextual hint cancellation, pan/marker/legend/expiry with both motion settings); `test/map_records_test.dart` (freshness/accuracy validation); `test/rule_language_test.dart` (typed Map snapshot fields). Actual fix availability remains a device check. |
| Cross-app session confirmation | `test/session_overlay_test.dart` (note/end transaction, acknowledgement order, rollback/replay, legacy/empty notes and narrow permission hints); native compile/install plus manual permission, Back/cancel and other-app input checks |
| Shared permission hints | `test/permission_hints_test.dart` (eight feature gates, narrow/enlarged text, cancellation/Back, already granted/Manage access, duplicate requests, failure recovery and running-session cache before cancellation); device review for actual Android grants/denials |
| Home note autosave | `test/home_note_test.dart` (batched writes, cursor changes, IME composition, blur/navigation flush, pending clock-out and ended-session guard) |
| Committed data-action feedback | `test/data_feedback_test.dart` (in-memory session save/edit/delete, cancellation, notice surviving form dismissal, pending/failed operations never announcing success) |
| Top error pills/form validation | `test/toast_test.dart` (replacement, expiry, dismissal, narrow 2× text, reduced motion, invalid transaction and syntax diagnostics) |
| Activity storage/backup/native session import | `test/activity_test.dart`; `test/record_location_test.dart` covers opt-in foreground capture, session/Finance positions, failed/denied fixes, backdating, Finance updates, rollback and trigger migration |
| Purchase receipts/settings/toast replay and rollback | `test/transaction_notification_test.dart` |
| Compiler/typed fields/targets/schedules | `test/rule_language_test.dart` |
| Syntax workspace/navigation/completion/Run/Stop | `test/rule_editor_test.dart` (separate log drawer, full-height workspace, Back, narrow enlarged text, completion and saved enabled flags) |
| Position freshness/full-range query/map catalog | `test/map_records_test.dart` |
| Shared loading placeholders | `test/skeleton_test.dart` (unchanged value geometry, reduced-motion static state, pulse disposal, semantics, blocked placeholder interaction, save guards and log loading); preserve `test/startup_test.dart` |
| Compact map toolbar/record selection/trace/recovery | `test/map_screen_test.dart` (inline mode/arrow navigation, advanced custom date/time controls, disabled Custom arrows, late location camera fitting, unlocated logs, top alignment, centered vertical tool rail, horizontal legend scrolling, narrow/enlarged text, landscape, zoom, selection/trace and tile retry) |
| Native local reminder clock calculation | `android/app/src/test/java/com/frekihub/freki_hub/RuleNotificationScheduleCheck.java` |

Example targeted run:

```powershell
flutter test test/rule_language_test.dart test/rule_editor_test.dart
```

The Java reminder check is a standalone main method with ten clock assertions, not a standard JUnit suite automatically executed by `flutter test`. It needs compiled Kotlin production classes and the matching Kotlin/JVM classpath; do not claim it ran unless explicitly compiled/executed. Temporary native-check artifacts from earlier sessions are disposable and are not a reproducible checked-in build script.

Widget tests use in-memory Drift and fake native channel responses. Map tests inject memory tiles; they do not verify live Geoapify availability. Use `tester.runAsync` for real asynchronous setup when necessary and `addTearDown(db.close)` for database cleanup outside the widget fake clock. A hanging test cleanup does not prove the app startup is hung.

## Generated database code

Edit table definitions/migrations in `lib/data.dart`, not `lib/data.g.dart`. When typed schema changes require regeneration, run:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

This command replaces conflicting generated outputs; use it only for a schema/code-generation change, with the worktree checked first. Keep schema migration, indexes, raw activity logs, restore/export and meaningful migration checks together. Plain documentation, UI or rule-field edits do not require regeneration.

## Native verification without an APK

When Kotlin changes, the compile task can be checked separately. Gradle may invoke Flutter through task dependencies, so explicitly exclude the Flutter build task when the user has not authorized an APK build:

```powershell
Push-Location android
./gradlew.bat :app:compileDebugKotlin -x :app:compileFlutterBuildDebug --no-daemon '-Pkotlin.compiler.execution.strategy=in-process' --console=plain
Pop-Location
```

This requires normal generated plugin/native resource inputs to be present. IDE-held resource locks may require closing the locking task or a deliberate temporary Gradle output override; do not delete user work or assume a local `.tmp` helper is checked in. Compiler success verifies source compatibility, not notification/permission delivery.

For the observed Java loopback/temp failure, set `JAVA_HOME` to the installed JDK and `JAVA_TOOL_OPTIONS` to `-Djdk.net.unixdomain.tmpdir=ABSOLUTE_WORKSPACE_TMP`. `ABSOLUTE_WORKSPACE_TMP` means the checked workspace `.tmp` directory. Keep this host workaround out of production behavior.

## Authorized device testing

Only build/install when the user asks or connects a device for that purpose. Check actual connection with `flutter devices`/`adb devices`; USB-debugging intent alone is not proof of a connected authorized phone. Do not install an emulator or work on iOS unless requested.

For an authorized development reinstall, use `installDebug` from the Gradle wrapper. It builds the necessary local debug APK and installs it on the connected phone; it does not publish or upload the app. Reuse incremental outputs and preserve app data. Avoid separate release/store packaging, clean builds or uninstalling unless explicitly requested.

```powershell
adb devices
./android/gradlew.bat -p android :app:installDebug
```

The command above is for this Windows workspace; from `android` on a Unix host, use `./gradlew installDebug`. Confirm the intended device before installing. Retain the documented Java/temp/output-directory workaround where necessary. Use `flutter run -d DEVICE_ID` when an attached development session/hot reload is wanted; use the real `DEVICE_ID` from the listing. For a profile performance run, use `flutter run --profile -d DEVICE_ID` with device-testing authorization. Do not claim frame time improvements from debug widget tests. Release tasks require external owner signing credentials; debug signing is not a release fallback. Debug installation remains the development workflow.

### Fast development loop

During authorized phone testing, keep the installed debug app open and attach once:

```powershell
flutter attach -d DEVICE_ID
```

Use the actual connected device ID. Confirm the tool reports a successful attachment and reload controls; attachment/VM-service discovery has previously failed in this workspace, so the command alone is not evidence of a working connection. Resolve USB forwarding/service discovery before defaulting to another full build. An authorized `flutter run -d DEVICE_ID` can establish a new attached session when needed, but it may build/install the app.

| Change or check | Preferred workflow |
| --- | --- |
| Supported Dart UI changes: layout, cards, colors, selectors, animations | `r` for hot reload; preserves current app state |
| Initialization/state changes not applied by reload | `R` for hot restart; resets Flutter state |
| Feature logic or regression | Relevant targeted checks from the test-routing table |
| Kotlin, manifest, native plugins or unsupported reload changes | Incremental `installDebug` when reinstall is authorized |
| Frame timing, memory or scrolling optimization | Profile mode plus DevTools on the physical phone |
| Startup, reopening or background lifecycle | Explicit lifecycle checks; hot restart is not a cold launch |

Flutter's [hot reload guide](https://docs.flutter.dev/tools/hot-reload) describes reload limits; the [performance guide](https://docs.flutter.dev/perf/ui-performance) explains physical-device/profile-mode measurement. Prefer this loop over reinstalling for every UI edit. Keep normal feature documentation and commit/push delivery; avoid repeated broad tests without new evidence.

The focused device checklist covers cold open/reopen/Retry, light/dark and enlarged text, reduced motion, selector/wheel cancel/confirm, long-press quick add, active-service clock-out, HyperIsland fallback, notification permission denial/retry, sound settings, location-off behavior, enter/exit radius, periodic samples, daily/weekday reminders, purchase listener formats, map network failure and backup/reset. Force-stop must be tested separately from normal closing; it intentionally suspends background execution until reopening.

### Geoapify map configuration

Map uses Geoapify's [osm-carto raster tile endpoint](https://apidocs.geoapify.com/docs/maps/). Copy `config/geoapify.example.json` to `config/geoapify.local.json` and replace the placeholder locally. The local file is Git-ignored; never commit its key. This workspace already has the user-supplied key configured. Supply it when starting Flutter:

```powershell
flutter run -d DEVICE_ID --dart-define-from-file=config/geoapify.local.json
```

For an authorized incremental Gradle debug install, pass the same Dart define:

```powershell
$mapConfig = Get-Content config/geoapify.local.json -Raw | ConvertFrom-Json
$mapDefines = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("GEOAPIFY_API_KEY=$($mapConfig.GEOAPIFY_API_KEY)"))
.\android\gradlew.bat -p android "-Pdart-defines=$mapDefines" :app:installDebug
```

Changing a compiled Dart define requires recompilation; attaching/hot restarting an existing binary cannot add a missing key. Once the configured debug binary is installed, attach with `flutter attach -d DEVICE_ID --dart-define-from-file=config/geoapify.local.json` so recompilation during hot reload retains the same key. Ordinary map UI changes retain the hot reload workflow. Build-time injection keeps the key out of Git but does not make a client API key secret from someone inspecting the app binary. Missing configuration skips tile requests and leaves recorded markers/log controls available. Geoapify receives tile requests for the visible viewport; saved log details are not uploaded or geocoded. Tests use fake keys and in-memory tiles.

## Troubleshooting

### Capture an Android UI error without rebuilding

For the easiest Windows workflow, open the installed app on the connected phone, then run `./tools/debug-logs.ps1` from the project root. Reproduce the error and press Ctrl+C. The script selects the only authorized device, captures only FrekiHub's process and saves timestamped output under ignored `.tmp/logs`. If both a phone and emulator are connected, pass `-DeviceId DEVICE_ID`. Restart capture after a process restart; its PID filter belongs to the process that was running at capture start. This does not build, install or clear anything.

An emulator can use the same log capture, but requires an installed Android 15/API 35-or-newer system image for this app. Before installing one, check disk space, memory and [hardware acceleration](https://developer.android.com/studio/run/emulator-acceleration). The emulator requires at least 5 GB free at startup **after** SDK/image/virtual-device installation, per [Android troubleshooting](https://developer.android.com/studio/run/emulator-troubleshooting). Do not install it into insufficient storage or delete personal files to create space. Emulator permission/location tests do not verify Xiaomi HyperIsland or OEM background behavior.

Settings activity logs contain saved actions, not Flutter exception stack traces. Connect the phone with USB debugging, authorize the computer, open FrekiHub and capture [Android Logcat](https://developer.android.com/tools/logcat) in PowerShell from the project root:

```powershell
$adb = 'C:/Users/ranbing143/AppData/Local/Android/Sdk/platform-tools/adb.exe'
& $adb devices
New-Item -ItemType Directory -Path .tmp -Force | Out-Null
& $adb -d logcat -v threadtime 'flutter:V' 'AndroidRuntime:E' '*:S' | Tee-Object -FilePath .tmp/calendar-log.txt
```

`-d` before `logcat` selects the single USB device; use `-s DEVICE_ID` instead if more than one is connected. Reproduce the error by opening the Calendar/date while capture runs, then press Ctrl+C. Retain the full exception and following stack frames, not just “Unsupported operation”. This reads logs from the installed app and does not build, install, clear records or clear the system log buffer. Keep captures in ignored `.tmp` and review them before sharing because diagnostics can contain personal details.

Calendar empty-date follow-up (2026-10-04): the agenda previously called `sort` on the constant empty fallback returned when a date had no sessions. Sorting a copied list prevents `Unsupported operation: Cannot modify an unmodifiable list` and avoids modifying the indexed session list. A narrow/enlarged-text page regression now navigates to an empty month.

| Symptom | Start here |
| --- | --- |
| Loader hangs | `startup.dart`, `watchAll`, startup tests; retain six-/fifteen-second recovery paths |
| SQLite JNI library missing after clean build | Run `flutter pub get`; avoid `flutter build ... --no-pub` with missing plugin registration |
| Session data saved but notification absent | Posting permission, foreground-service restrictions, native logs and pending ID; do not delete the session |
| Purchase missing from Finance while closed | Native event queue versus Flutter import; selection/listener access/parser eligibility |
| Reminder late or absent | Posting/channel permission, exact access, enabled rule, selected weekday, force-stop/OEM restrictions |
| Location rule stays idle | Fine/background access, system location, Play services, sample age/accuracy/radius; unknown location is not outside |
| No map dots | Time/category filters, usable logged positions, logging opt-in; tile availability is separate from record availability |
| Calendar/Finance mismatch | Calendar retains original denominations; Finance filters currency; planner date/occurrence status differs from actual entries |
| Test freezes after interaction | Fake-clock timers/database teardown or missing native mocks; isolate the relevant existing test |

## Delivery and documentation

Preserve unrelated changes. Update current references and syntax docs in the same feature commit; keep historical audit counts explicitly historical. Verify local documentation links and code paths when editing guides. Commit/push completed features to the existing private origin as requested; do not change visibility, rewrite shared history, publish app binaries or add secrets.

## Audit regression and storage checks — 2026-10-06

`test/audit_regression_test.dart` covers final planner overflow, stale recomputation/occurrence uniqueness, malformed log rollback, backups above the former 20 MiB limit, fixed manual action time, committed-prefix batched retry and cluster membership. `test/audit_ui_test.dart` covers recoverable Logs, Calendar restoration/leap-day navigation and session display formats. Overlay and rule-language tests cover historical position replay and typed delivery/queue/projection diagnostics. Use the full suite once for this app-wide pass; these are disposable in-memory/widget checks, not a phone performance test.

For phone storage, measure Android's app-size/user-data/cache breakdown before attributing growth. ADB must show the authorized device; local APK sizes do not establish installed storage. Do not clear data or uninstall to optimize size. During a subsequent authorized debug install, an ARM64-only build may use `-Ptarget-platform=android-arm64` after verifying the phone ABI; this preserves debug/hot reload and avoids bundling other architecture engines. Do not hard-code an ABI for every supported device or switch to a release build without user direction. See [Flutter app size](https://docs.flutter.dev/perf/app-size).

Release signing inputs are `FREKIHUB_KEYSTORE_PATH`, `FREKIHUB_KEYSTORE_PASSWORD`, `FREKIHUB_KEY_ALIAS` and `FREKIHUB_KEY_PASSWORD`, provided outside Git by the owner. `verifyReleaseSigning` guards Release tasks and checks the keystore file. No owner key is generated here, and setting credentials does not authorize release packaging/publishing.

AGP 9 compatibility flags remain required by the installed Flutter/plugin combination: file_picker, connectivity_plus, JNI and share_plus still apply legacy Kotlin Android integration. Do not remove flags blindly or modify the global package cache. Coordinate migration with compatible plugin releases and [Flutter's built-in Kotlin guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin). HyperIsland 0.4.4 removes the current small-icon/action-key timer API; the existing 0.4.0 integration is retained pending a tested control migration. SDK XML-tool metadata mismatch is a host-toolchain issue, not an app runtime failure.

Flutter commands regenerate ignored `android/local.properties`; normalize SDK/Flutter drive-colon escaping after those commands before host lint. Keep those host paths out of Git. A stale incremental resource merge after qualifier consolidation was recovered by rerunning only `:app:mergeDebugResources --rerun`; no clean/data reset was used.
