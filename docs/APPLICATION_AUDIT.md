# FrekiHub application audit

Audit date: **2026-10-02**. Starting code revision: `f91f75e`. This pass reviews product structure, data contracts, native background paths, selectors/motion, startup, tests and documentation. It is a source and automated-regression audit, not a device visual review, security certification or benchmark.

## Initial verification results

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
| Sessions | Phone list, bounded scrolling/table, stable sort, custom filters, width preferences, confirmed bulk delete | Saved-rule banner now describes all automation accurately; individual Run/Stop state remains in Settings |
| Finance | Integer money, currency isolation, occurrence uniqueness, expected/actual timeline, post-commit receipts | Closed-Flutter purchases are queued until reconciliation; long timeline/charts need device profiling |
| Calendar | Real session/entry agenda, date indexing, four views, draggable month collapse, shared two-position day drawer | Starts at today/month on remount; DST-sensitive date navigation and enlarged/short layouts need broader tests |
| Settings | Shared custom selectors/sheets, separate notification sounds, backup/reset confirmation and error handling | OS permission/channel flows unverified; unbounded export can exceed restore's size limit |
| Logs / automation sheets | Opt-in logging, completion, parser diagnostics, target scoping, paused Save and Run/Stop, sampled native context | Log UI caps 1,000 rows; not every edit/delete/action is logged; native queue is unbounded |
| Forms and shared chrome | Themed wheel inputs/selectors, guarded saves, accessible tooltips, shared motion/feedback and inset handling | Current automated layout coverage is narrow portrait at 1.3× text, not every overlay/form/landscape state |

## Findings and current status

These findings originated in the initial documentation audit. They remain unresolved unless explicitly marked resolved below. Recheck their source and add focused regression coverage when implementing a change; follow-up evidence appears at the end of this document.

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

Status: **partially resolved, 2026-10-02**. Map tile failures now provide a retry that resets the tile layer and evicts failed images; record-query failures can retry separately. Selected records/dots are preserved during tile retry. Compact controls adapt to short screens, and large badges display `99+` with exact counts retained in accessibility/detail content. The Map widget regression covers retry-triggered image reload, retained selection/trace, a 320 px enlarged-text portrait layout and non-overlapping controls at 640×360; coordinate/query tests also passed (four focused tests total). Static analysis reported no issues. The final widget check verifies zoom activation after map readiness; readiness now rebuilds controls so they cannot remain disabled after initialization.

Remaining: full-year/all-range queries materialize every record and marker group. Unchanged-row skips/cache limits help, but no long-history benchmark or spatial clustering exists. Real network/offline recovery and native GPS permission/provider failures require phone verification. The user's precise location error was not identified from an error message; Map itself does not request GPS. Profile before adding heavy dependencies; preserve named legends, complete query semantics and truthful sampled traces.

### F07 — Session condition banner is broader than its label — resolved

Priority: low. The banner still links to all saved automation, including notification/Finance-only and paused rules. It now says “Automation rules saved” and directs users to Settings for individual Run/Stop status. It no longer claims that every saved rule is a session condition or that the global location toggle represents every rule. Source checked in `lib/history.dart`; the full widget suite passed.

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

## Session drawer follow-up — 2026-10-02

Source-confirmed: session list tiles used a full-screen `OpenContainer` transform instead of the shared bottom sheet. That path is replaced by `panel`; all shared drawers now snap at 56% and 92% of the available viewport, with coordinated primary scrolling, a draggable/tappable accessible handle, keyboard expansion and reduced motion. Calendar's nested day drawer is removed. Empty/loading lists and non-scrollable picker/quick-action content now attach to the shared scroll controller. The date wheel uses the available width to avoid an overflow at 320 px with 1.3× text.

Automated evidence: seven focused layout, Map and rule-editor tests passed, including frame-by-frame session opening, both snap points, nested selectors/date wheels, keyboard insets and cancellation. The Map check expands the compact drawer before asserting all lazy list rows are present. No saved records are changed by the opening test.

The reported opening error was not captured in the recent device logs. Removing the former opening path and passing regressions do not establish its exact original cause, nor measure real-device frame performance. Static analysis passed with no issues. This follow-up did not build/install an APK or measure phone performance; device verification remains pending.

Fixed-header follow-up (2026-10-02): Today's title/date now sit outside the bounded content ListView. All three existing layout tests passed, including explicit unchanged title/date positions after scrolling at enlarged text scale. Other pages retain their existing scrolling headers.

Today UI follow-up (2026-10-02): compact header between fixed shortcuts, fitted all-time currency-isolated balance pill, page-top add buttons removed, and live idle flip time switching to elapsed time when running. `budget.balance` is documented and registered for typed automation completion/snapshots. Static analysis passed and 13 existing layout/compiler/editor tests passed, including narrow enlarged-text layout and cross-month/currency balance checks. Incremental debug assembly succeeded in 2m 41s (151 of 175 tasks up-to-date), then installed on the connected Android device. Device captures confirmed header/pill fit and advancing active-session digits without ending the session. Idle presentation was widget-checked; idle ticking was not separately tested on the phone because a session was active. No personal captures or APKs were committed.

When device testing is authorized, prioritize repeated cold closes/reopens, foreground notification clock-out, HyperIsland fallback, location-off/denied permission behavior, inside/exit ownership, time-only background service starts, denied/channel-blocked reminders, weekday/time-zone changes, payment format/import/receipt deduplication and map offline recovery. Then profile representative long session/finance/location histories. These are follow-up recommendations, not completed checks or permission to build now.

## Whole-app source and feedback audit — 2026-10-02

Reviewed the six page surfaces, shared navigation/drawers/selectors/forms, startup, data/restore contracts, rule compiler/editor, reconciliation, and Android service/notification/location transport. This pass began at `d7ab27c` with ongoing drawer work already present. That work is preserved and is described separately above. No device visual review, APK build/install, native compilation or performance measurement was performed for this pass.

### Fixed feedback inconsistencies

- Action errors previously used a mixture of inline fields, plain form text, a Today dialog and top toasts. Submitted form errors, list-name validation, savings-goal failures, syntax diagnostics and guarded operation failures now share a dismissible top pill. Persistent startup Retry and Map availability states remain on their pages.
- Toasts previously overlapped, filled nearly the entire width and had no dismissal control. The new pill replaces the previous message, sizes to its content up to 560 px, uses safe insets, bounds long diagnostics and provides a dismiss button/live-region semantics. Errors last eight seconds; other notices last four. Reduced motion skips the slide/fade.
- Category/payment-method changes previously updated the visible list and cleared input before persistence, with no failure handler. They now commit first, retain input on failure and disable duplicate writes while saving. Transaction deletion and savings-goal persistence now catch failures and keep their forms open.
- Guarded actions, Today and foreground reconciliation no longer show raw database/platform exception strings. Existing validation messages and syntax line/column details are retained.
- F07 is resolved by accurate saved-automation wording.

### Additional source-confirmed findings

#### F11 — Some async UI callbacks still bypass guarded feedback

Priority: medium. Finance occurrence status changes, planner duplicate/delete/reorder (`lib/budget.dart`), session date/time preference changes (`lib/history.dart`), appearance/currency preferences (`lib/settings.dart`), and selected payment-app saves/condition deletion (`lib/activity.dart`) contain direct awaited writes without their own error handler. `withFeedback` invokes the callback without awaiting its future; the outer handler that opened a sheet does not catch a later button's failure. These paths can fail without the new error pill. The form deletion, goal and managed-list paths were fixed here; the remaining callbacks need a bounded follow-up and injected write-failure coverage. Successful-path widget tests do not prove failure delivery.

#### F12 — Logs stream errors can look like an empty journal

Priority: medium. `ActivitySheet.logs` uses `snapshot.data ?? []` without testing `snapshot.hasError`. A database stream error with no data displays “No activity yet” and advice to enable logging, rather than a load failure/Retry state. With prior data, the view can show stale records without indicating failure. Source: `lib/activity.dart`, Logs StreamBuilder. Needs a stream-error regression test and a persistent recoverable state.

#### F13 — Session editing ignores display-format preferences

Priority: low. Session lists/previews use `sessionDate` and `clockTime`, but `SessionForm` clock-in/out labels hard-code `d MMM yyyy, HH:mm`. Choosing a 12-hour clock or another date format in Settings does not carry into the editing sheet. Source: `lib/forms.dart`. Use the existing formatting helpers and verify 12/24-hour and date-format examples in a future change.

F06 additional evidence: `MapScreen.watch` sets `loadError` after a record-stream error but does not clear it when subsequent rows succeed. Its unchanged-row fast path may also return before clearing the error. The tile-error flag similarly has no explicit recovery/reset. Preserve saved dots and expose recoverable errors without treating network availability as record availability.

### Rechecked outstanding risks

F01 debug release signing, F02 queued closed-Flutter purchases, F03 swallowed native timer-start failures, F04 unbounded native events, F05 export/restore size disagreement, F06 Map recovery/history cost, F08 Calendar remount/date arithmetic, F09 apparently unused dependencies, and F10 incomplete restore/log validation remain unresolved. No retention policy, database schema, automation language, platform minimum or permission behavior was changed in this pass. `budget_page` compatibility destinations, integer money/currency isolation, transactional reconciliation and commit-before-receipt behavior are retained.

### Fresh automated evidence

- Flutter static analysis: no issues.
- Full Flutter suite: **34 tests passed**, including four new feedback regressions and the current drawer/layout checks.
- Changed documentation's local links and `git diff --check`: passed.
- New feedback coverage checks both motion settings, 320×480 at 2× text with a status-bar inset, replacement without stale-timer dismissal, explicit/automatic dismissal, invalid transaction remaining editable with no insert, and invalid syntax retaining line/column diagnostics without running.
- Tests use in-memory storage and simulated widget/platform inputs. Existing Map tests use memory tiles. Real phone visuals, screen-reader announcements, keyboard/landscape combinations, OS permission flows, background delivery, live payment capture and large-history performance remain device gaps.
