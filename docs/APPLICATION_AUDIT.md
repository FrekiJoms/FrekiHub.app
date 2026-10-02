# FrekiHub application audit

Audit date: **2026-10-02**. Starting code revision: `f91f75e`. This pass reviews product structure, data contracts, native background paths, selectors/motion, startup, tests and documentation. It is a source and automated-regression audit, not a device visual review, security certification or benchmark.

## Verification results

- `flutter analyze`: no issues.
- `flutter test --reporter expanded`: **29 tests passed** across the existing nine Flutter test files.
- Source checked for six pages, shared parts/design, forms, storage/migrations/projections, rule compilation/editor, event reconciliation, native services/receivers, notifications and map integration.
- Android foreground-service, alarm and geofencing documentation checked against the background explanations in [Android runtime](ANDROID_RUNTIME.md).
- No APK build/install, phone screenshots, permission-flow run, live payment notifications, battery test or measured frame/launch profiling performed.
- Standalone native reminder clock assertions were inspected, not rerun in this documentation audit. Previous native compilation is historical evidence, not a fresh result here.

Passing automated tests shows their covered cases pass; it does not establish the absence of all bugs or prove every button/function on a real device.

## Page-by-page findings

| Surface | Source-confirmed strengths | Remaining verification / issue |
| --- | --- | --- |
| Today | Isolated timer digits, split-flap/reduced-motion behavior, native chronometer, guarded clock controls, midnight refresh | Native service delivery/HyperIsland and cold reopen need phone tests; manual one-per-day behavior differs from other write paths |
| Map | Full interval query, freshness validation, named categories, grouped records, selected chronological trace, debounced context and unchanged-row skip | Long-history cost, very large grouped badges, offline recovery and short-screen overlays need further work/testing |
| Sessions | Phone list, bounded scrolling/table, stable sort, custom filters, width preferences, confirmed bulk delete | Condition banner currently checks all automation rules rather than session-relevant running rules |
| Finance | Integer money, currency isolation, occurrence uniqueness, expected/actual timeline, post-commit receipts | Closed-Flutter purchases are queued until reconciliation; long timeline/charts need device profiling |
| Calendar | Real session/entry agenda, date indexing, four views, draggable month collapse, debounced day-sheet extent | Starts at today/month on remount; DST-sensitive date navigation and enlarged/short layouts need broader tests |
| Settings | Shared custom selectors/sheets, separate notification sounds, backup/reset confirmation and error handling | OS permission/channel flows unverified; unbounded export can exceed restore's size limit |
| Logs / automation sheets | Opt-in logging, completion, parser diagnostics, target scoping, paused Save and Run/Stop, sampled native context | Log UI caps 1,000 rows; not every edit/delete/action is logged; native queue is unbounded |
| Forms and shared chrome | Themed wheel inputs/selectors, guarded saves, accessible tooltips, shared motion/feedback and inset handling | Current automated layout coverage is narrow portrait at 1.3× text, not every overlay/form/landscape state |

## Unresolved findings

These findings are documented, **not fixed by this documentation-only commit**. Recheck their source and add focused regression coverage when implementing a change.

### F01 — Release signing is not production-ready

Priority: high for an app-store release; not a private source-repository blocker. `android/app/build.gradle.kts` assigns the debug signing configuration to release. A signed store build needs deliberate key management and release configuration. Do not invent/upload signing secrets or treat private Git publishing as an app release.

### F02 — Finance has no immediate closed-Flutter commit

Priority: medium, product expectation gap. `PurchaseListener` queues structured JSON; only `AutomationSync._reconcile` inserts Drift expenses and durable receipts. A payment detected with Flutter closed will not appear as a committed Finance entry or generate its saved confirmation until reconciliation. Accurate documentation resolves the misleading claim, not the implementation gap. A future native/shared database writer requires an explicit migration/concurrency design.

### F03 — Time-only background timer start can fail silently

Priority: medium. `Automation.applySessionTransition` writes session state and emits `auto_clock_in` before attempting a foreground service. Its catch suppresses all service-start exceptions. A non-geofence background evaluation can be restricted by Android, leaving recorded timing without the expected native notification. Add diagnostics and design a platform-compatible fallback before promising reliable time-only outside-app clock-in. Actual occurrence on the user's device remains unverified.

### F04 — Native event queue has no bound or retention policy

Priority: medium for sustained collection. `Automation.emit` reparses/rewrites a JSON array and commits synchronously. All unacknowledged events remain in SharedPreferences. Extended closed-app logging can increase memory/I/O cost and import latency. Investigate an append-friendly bounded/durable transport with explicit loss/retention semantics; do not silently drop logs to optimize it.

### F05 — Export and restore size policies disagree

Priority: medium. `AppDatabase.backup` builds the full history/preferences JSON with no size bound. Settings rejects restore files above 20 MiB. An exported large backup can be impossible to restore through the UI. A future solution should align limits or stream/segment export/import while preserving rollback and full history.

### F06 — Map failure recovery and large history need work

Priority: medium/low. `MapScreen` sets a tile-error flag without an explicit retry/reset action; it keeps dots usable but cannot clearly signal recovery. Full-year/all-range queries materialize every record and marker group, while very large group counts use a small badge. Unchanged-row skips/cache limits help, but no long-history benchmark or spatial clustering exists. Short landscape layouts can crowd fixed controls. Profile before adding heavy dependencies; preserve named legends, complete query semantics and truthful sampled traces.

### F07 — Session condition banner is broader than its label

Priority: low. `HistoryScreen` shows “Session conditions set” whenever automation contains any rule, including notification/Finance-only or paused structured rules. Its subtitle follows the global location toggle, which does not represent all non-location programs. Filter by actual session actions and enabled state or rename the banner to describe all automation accurately.

### F08 — Date/view state restoration is incomplete

Priority: low. `CalendarScreen` exports selected date/view preferences but initializes at today/month on remount. This is a documented behavior, not persisted restoration. Some Calendar next/week/day operations still use duration arithmetic; review DST boundaries if restoring navigation state or supporting additional zones. Map date ranges already use calendar-aligned boundaries.

### F09 — Apparently unused direct dependencies

Priority: low. A source search found no Dart use of `shared_preferences` or `CupertinoIcons`, though the direct packages remain in `pubspec.yaml`. Android SharedPreferences usage does not require the Dart plugin. Verify generated/plugin/platform dependencies and device startup before removing packages; no dependency was removed in this pass.

### F10 — Restore/log coverage is narrower than a complete activity journal

Priority: low. Raw activity-log JSON is not comprehensively schema-validated during restore; SQL constraints/transaction rollback provide part of protection. Trigger logging covers inserts and the initial end transition, not edits/deletes/all UI actions. Document these boundaries; new log types need explicit schema/provenance handling and should not be represented as recorded when absent.

## Preserved invariants

Keep one running session, integer money, original record currencies, occurrence and event deduplication, pending-end replay safety, commit-before-confirmation, location freshness, unknown-target/action rejection, branch-change execution, source/program/snapshot/outbox separation, opt-in collection, reduced motion and sound preference. User records must never be cleared as a recovery shortcut.

## Documentation corrections in this pass

The root README now presents current navigation/features and points to complete references. The previous README is retained under `docs/history` so historical implementation notes are not lost. `UI_AUDIT.md` is marked historical and links here. New `AGENT.md` gives fast onboarding; `AGENTS.md` remains canonical agent instructions. Guides distinguish local notifications from server push, queued detection from saved data, planner rules from automation rules, current source from legacy iOS claims and test results from on-device measurement.

## Build follow-up — 2026-10-02

An explicitly requested debug rebuild exposed a manifest incompatibility: HyperIsland ToolKit 0.4.0 requires API 35 while Flutter's default minimum was API 24. Resolved by declaring `minSdk = 35` in the app Gradle configuration; this APK now requires Android 15 or newer. Debug assembly succeeded using a temporary app output override because another process held the standard output's `R.jar` open. Compilation, manifest merge, native library compilation and APK packaging passed. Existing Gradle/SDK deprecation warnings remain; this is not evidence that all device flows pass.

## Recommended next validation

Today UI follow-up (2026-10-02): compact header between fixed shortcuts, fitted all-time currency-isolated balance pill, page-top add buttons removed, and live idle flip time switching to elapsed time when running. `budget.balance` is documented and registered for typed automation completion/snapshots. Static analysis passed and 13 existing layout/compiler/editor tests passed, including narrow enlarged-text layout and cross-month/currency balance checks. Incremental debug assembly succeeded in 2m 41s (151 of 175 tasks up-to-date), then installed on the connected Android device. Device captures confirmed header/pill fit and advancing active-session digits without ending the session. Idle presentation was widget-checked; idle ticking was not separately tested on the phone because a session was active. No personal captures or APKs were committed.

When device testing is authorized, prioritize repeated cold closes/reopens, foreground notification clock-out, HyperIsland fallback, location-off/denied permission behavior, inside/exit ownership, time-only background service starts, denied/channel-blocked reminders, weekday/time-zone changes, payment format/import/receipt deduplication and map offline recovery. Then profile representative long session/finance/location histories. These are follow-up recommendations, not completed checks or permission to build now.
