# FrekiHub application audit

## Remediation after full scan — 2026-10-06

S01–S04 and S07–S09 have source fixes: bounded/recomputed planner amounts, transactional typed log validation, aligned 128 MiB backup policy/isolate JSON, fixed Home action instants, Logs error/Retry, common provider lookup and explicit OS backup exclusions. S05 has native diagnostics/fallback/resume retry; S06 has segmented durable queues, committed-prefix batches and explicit sample backpressure. Calendar restoration/date arithmetic, session formats, Map clustering/selection pruning, 32 MiB map cache, unused dependency removal, compatible dependency updates, adaptive masking and release-signing gates are also implemented.

Verification: the full Flutter suite passed 109 checks; the final affected planner/reconciliation suite passed 20 checks after the additional batch-ordering and monthly-base overflow guards. Flutter analysis and final affected Dart analysis reported no issues. Native Kotlin compilation and Android lint passed with 0 errors and 75 warnings; the production reminder-clock check passed 10 cases. Documentation links and diff whitespace were checked. No APK was assembled/installed; automated tests do not establish phone performance or native queue crash recovery.

Remaining boundaries: essential queues/history are retained without silent eviction; Map queries still materialize the complete selected range; Android queue process-death migration, actual location/timer/backup transport and profile behavior require a phone. No phone is connected, no APK was assembled/installed and no records were cleared. Legacy Kotlin/AGP flags require coordinated third-party plugin migration, HyperIsland 0.4.4 needs a compatible clock-out control migration, and SDK XML metadata warnings belong to host tooling. Owner release-signing credentials remain unprovisioned. Closed-Flutter Finance saves still reconcile through the existing SQLite owner, and Logs is not a journal of every autosave/deletion.

The historical scan/follow-up statements below describe their original review state; this section and the updated F01/F03–F05/F08–F10 entries supersede their outstanding-status claims.

## Full scan — 2026-10-05

See [Full application scan](FULL_SCAN_2026-10-05.md) for current source evidence, severity and reproduction details. Full Flutter suite: **97 passed**; native reminder clock check: **10 passed**; two synthetic probes confirmed a percentage-projection/restore limit defect and accepted malformed log timestamps. Flutter analysis reported four Map lint infos, with no error/warning/deprecated Dart API diagnostics. Kotlin compilation passed; Android lint failed with two ignored local.properties path-escaping errors and 101 warnings. Deprecated AGP compatibility flags, native legacy branches and outdated packages were identified. The latest foreground location path also delays Home action timestamps until acquisition completes. No app behavior or phone records were changed in this scan.

Current corrections to older entries: Map stream recovery clears errors and checks them before skipping unchanged rows; Finance updates are now logged. F12 refers to `LogsSheet` in `lib/logs.dart`, where stream errors leave initial skeletons or stale data without Retry. Old `lib/activity.dart` references predate the Logs/Syntax split. The app's OS backup policy is implicit; the earlier no-cloud-copy wording does not establish exclusion from Android system backup. Remaining findings and device gaps are detailed in the new report.

## Manual record location persistence — 2026-10-05

Confirmed: manual Home/form/Finance writes previously never requested a fix. Triggers copied a periodic native cache, checked the label against wall-clock time but retained coordinates unconditionally, and Finance updates had no log. Resolved in source with shared opt-in foreground capture, atomic sample/record writes, matching label/position freshness against the event timestamp and meaningful Finance-update logs. Version 3 replaces triggers without modifying existing records/logs. Native event replay retains original snapshots and cannot regress the cache with old/invalid samples. Map still reads saved logs; it does not fabricate missing historical locations. Activity logging remains a separate opt-in requirement.

Verification: 25 targeted checks passed across record-location, migration, session/reconciliation, purchase receipts, data feedback and Home notes. Static analysis of affected source/tests passed; repository-wide analysis separately reported four existing Map lint infos. Physical fix availability and foreground clock/Finance actions require device review; ADB listed no connected phone. Legacy cross-app pending clock-outs without position payloads cannot request their historical position during later reconciliation; only a cached sample matching the event time can attach.

## Shared in-app skeleton loading policy — 2026-10-04

SkeletonValue/SkeletonList now cover non-startup loading: Map status only, Activity logs before data/first activity snapshot, Syntax builder records, form save actions, Home clock actions, syntax location/save/Run, active Settings export/restore and list-edit action slots. Preloaded Map dates and static section labels stay visible. Placeholders preserve value/action geometry, prevent interaction, hide stale semantics, announce the specific operation and pulse only while pending; reduced motion is static. Settings uses transient action/item identifiers so unrelated actions remain readable. App launch keeps StartupLoading, and determinate Finance charts retain their real progress values. No saved setting, database schema, rule syntax or native source change was added.

The single-line Map status still widens horizontally to its shortcut limits before ellipsizing, with unchanged height/top and legend position for longer text. An idle-frame tile failure now explicitly requests its queued visual update so Retry/status do not depend on an unrelated frame. The loading policy and reusable components are documented in AGENTS.md, APP_DOCUMENTATION.md and DEVELOPMENT.md for future work. Focused Map, syntax workspace, Home clock and startup checks passed. Shared skeleton tests cover dimensions, reduced motion, animation disposal, stale semantics, interaction blocking, save guards and pending log content; initial semantics-test cleanup was corrected and all four shared skeleton checks then passed, completing 19 passing focused checks across the affected loading, Map, syntax, Home and startup features. Documentation links and diff whitespace checks passed. Static analysis completed with No issues found and exit code 0; SDK stderr subsequently reported a DartWorker thread startup error during tool shutdown, without a source diagnostic. Flutter hot reload succeeded with the preloaded Map date restored. No phone scrolling or record edits were performed.

## Map counts inside the upper filter pill — 2026-10-04

Removed the lower range/status Chrome container identified in the annotated screenshot. The upper map-date-pill now contains map-record-counts below its date/arrow row, with 9 px type, 55% opacity and 4 px vertical padding. Its width follows content and available shortcut clearance; a bounded intrinsic measurement of this small control keeps arrows at their 10 px end insets when the count line is wider than the date. Counts retain visible located/unlocated information while Trace is on. Full date range remains in accessibility semantics and the existing picker. Loading/basemap notices reuse the upper pill, and Retry moves to the right-side tool rail. Legend spacing accounts for enlarged text and notices. All four focused Map checks passed, covering count ancestry/opacity/geometry, arrow edges, picker/menu gestures, narrow layouts, tracing and tile retry. Year-label expectations were updated after removing the duplicate lower caption. No saved data, map rules or native source changes were made by this feature. Device reconnection lost the previous VM service; attach/launch/activity refresh were attempted before the previously authorized incremental install fallback. Focused analysis reported no issues; documentation links and diff whitespace checks passed. Incremental :app:installDebug succeeded with the local Geoapify define, preserving data and the unrelated existing native edit. Flutter reattached, advertised its VM service and completed a verified hot reload. A screenshot confirmed successful Home startup; Android denied the attempted Map-tab review tap because input injection permission is unavailable, so Map visual review remains user-driven. No phone scrolling or saved-record edits were performed.

## Single-row date pill with end arrows — 2026-10-04

Removed the separate mode label/chevron row. The content-fit pill retains a 48 px height with a single centered date row and previous/next buttons 10 px from their corresponding edges. Local button sizing overrides the shared 48 px minimum to avoid extra theme-added arrow spacing. Long pressing the pill opens the existing themed choice menu; tapping the date keeps the original wheel/Custom panel. The central tooltip uses manual triggering so it cannot consume the menu gesture. All four focused Map checks passed, including exact edge insets, tap-to-wheel/cancellation, long-press mode changes, calendar navigation, disabled Custom arrows and narrow layouts. Documentation links and diff whitespace checks passed. The phone disconnected before reload; ADB reconnected but Flutter attach could not rediscover the VM service after app launch/activity refresh, and the previous endpoint was unavailable. The user subsequently requested debug installation: incremental :app:installDebug succeeded on the connected Xiaomi with the local Geoapify define and without clearing data. The app launched successfully; a screenshot confirmed Home and the active session, while Map visual review remains user-driven. Flutter reattached, advertised its VM service/reload controls and completed a verified hot reload. The existing unrelated native Automation.kt edit was preserved. No phone scrolling or record edits were performed.

## Content-fit date controller and themed long-press choices — 2026-10-04

The Map date pill now fits its label and arrow content with 25 px horizontal padding per side, capped only by available space between Calendar and Settings. It retains the compact 48 px height. Date/Week/Month/Year/Custom replaces the By prefix. Tapping the selector opens the original date wheel for standard modes or the existing advanced Custom panel; long pressing opens the reusable showChoiceMenu surface with theme colors, rounded corners, active-row tint/checkmark, floating depth and reduced-motion-aware animation. No picker replacement, map data or rule behavior changes. All four focused Map checks passed, including tap-to-wheel/cancellation, long-press mode changes, shrinking width, calendar navigation, disabled Custom arrows and narrow layouts. A test expectation was updated for the duplicate Month label while its menu is open. Focused library analysis, documentation links and diff whitespace checks passed. Flutter hot reload succeeded on the attached phone; no scrolling tests or record edits were performed. Menu appearance and profile timings remain for phone review.

## Compact inline date pill — 2026-10-04

The inline Map controller now fits a 48 px-high shared glass pill: 28 px date/arrow row, 16 px mode row and 2 px top/bottom padding. Its date label is 13 px, mode selector 9 px and arrows 14 px. Existing Day/Week/Month/Year navigation, advanced Custom range and ghosted Custom arrows are preserved. All four focused Map widget checks passed; documentation links and diff whitespace checks passed. After USB reconnection, VM discovery required an incremental :app:installDebug fallback with the local Geoapify define; installation succeeded without clearing data. Flutter attachment and hot reload then succeeded. A phone screenshot confirmed the compact top pill, disabled Custom arrows and rendered map; the open mode popup obscured its smaller selector, so that selector remains for user visual review. No phone scrolling or record edits were performed; profile timings remain unmeasured.

## Inline Map timeline and advanced custom range — 2026-10-04

Timeline navigation now sits directly between Calendar and Settings, with a mode dropdown for Day, Week, Month, Year and Custom. Arrows move by the selected calendar unit; only the compact label receives a 200 ms direction-aware slide/fade, with reduced motion preserved. Custom arrows are ghosted and disabled. Timeline logs moves to a separate button above the vertical right-side tools. No whole-map transforms, new tracking or inferred coordinates were added.

Custom uses the shared drawer for From/Through dates and optional start/end times with the original wheel pickers. End includes the chosen minute; default date-only ranges include the full Through day. Invalid/reversed ranges disable Apply. Cancellation keeps the original view. Exact ISO boundaries reuse existing preferences and query start-inclusive/end-exclusive epoch semantics. Numeric map.from_epoch/map.until_epoch provide completion, validation and snapshots; legacy date fields retain their date-component format. RULE_SYNTAX documents the precision and boundary behavior. The seven focused Map/query/catalog checks passed, including inline navigation and custom arrow disabling. An expanded focused check also passed next/previous behavior for Day, Week, Month and Year. Persisted precise snapshots and numeric field validation passed; focused analysis reported no issues after source lint corrections. Documentation links and diff whitespace checks passed. The initial layout hot-reloaded successfully, then the phone disconnected; ADB reported no connected devices and reattachment was unavailable, so final refinements remain for phone review. No APK reinstall, phone scrolling or saved-record edits were performed. Device profile timings are unmeasured.

## Map tool active indicator — 2026-10-04

The shared Map control renderer now gives toggle tools a selected state and a gray circular background when active. Trace uses a 43 px indicator circle (reduced by the requested 5 px) inside the unchanged 48 px touch target, and returns to a transparent background when off. Action controls remain ordinary buttons, with retained tooltips, feedback and 48 px targets. No trace data, selection or persistence behavior changes. All three focused Map checks passed with the final 43 px circle and retained 48 px controls. Selected state, circular shape and gray opacity were checked. The initial indicator passed focused analysis; final sizing hot-reloaded successfully on the attached phone. Documentation links and diff whitespace checks passed.

## Legend pill symmetry and edge fades — 2026-10-04

The latest requested spacing adds 5 px top/bottom padding around the compact Map legend row. Selection is now conveyed by opacity instead of a colored background: selected categories are fully opaque; unselected categories use a 40% ghost treatment. A shared-motion 150 ms fade respects reduced motion. A static horizontal alpha mask softens both scroll-strip ends; it does not intercept gestures or introduce an animation controller or extra backdrop blur. Labels remain single-line with retained category semantics, feedback and horizontal scrolling. All three focused Map checks passed, including the final padding, fade-mask presence, deselection/reselection opacity and existing map behaviors. The update hot-reloaded successfully to the attached Xiaomi phone. Documentation links and diff whitespace checks passed.

## Compact Map legend pill — 2026-10-04

Removed MAP from the legend strip at the user's request. The centered glass pill shrinks to content width, capped by screen margins, and retains horizontal scrolling for overflow. Single-line 11 px category labels, 13 px icons, compact chip density and reduced padding make the strip smaller. Category colors, selected semantics, filtering, feedback, shadows and the right tool rail remain intact. This supersedes the Map title addition below.

## Resume physical-phone design review — 2026-10-04

The compatible Xiaomi 25080RABDG (Android 16/API 36) reconnected. The incremental Gradle `:app:installDebug` completed successfully with the locally configured Geoapify Dart define; app data was preserved. Flutter attached with the same define file and advertised its VM service and reload controls. An inspected screenshot of the user's current Sessions page confirmed the uppercase title and stronger shortcut/navigation shadows. Map tile rendering and native picker appearance are ready for user review but were not established by that screenshot. No phone scrolling, record edits, session ending or permission changes were performed. Updated attachment instructions retain the define file for subsequent hot reloads.

## Floating overlay depth — 2026-10-04

Shared `FloatingDepth` strengthens static ambient/contact shadows around Chrome and floating toast surfaces, with theme-aware opacity. This applies across pages to navigation, Calendar/Settings shortcuts, Home balance, Map toolbar/legends/tools/captions and toast overlays. Quick-add menus, Flutter dialogs and the shared drawer use matching 16 dp Material elevation and shadow tint. Content cards retain their existing subtle shadow. The effect adds no layout padding, animations, extra blur filters or gesture changes. All twelve existing navigation, toast and shared-drawer checks passed, covering quick-add selection/cancellation, keyboard geometry, toast replacement/dismissal, content-fit/expanded sheets and reduced motion. Flutter analysis, documentation links and diff whitespace checks passed. Phone appearance/profile timings remain unverified while a compatible device is unavailable.

## Consistent primary page titles — 2026-10-04

All six page surfaces share `PageTitle` for uppercase headings without trailing periods, using HOME's 28 px bold style and 1.2 px spacing. PageBody uses the component for compact and standard headers. Map gains a glass-backed MAP title beside its scrolling legends without moving controls; Calendar labels its page and retains the selected year/month as a smaller caption. Finance compatibility names and destinations are unchanged. All eight focused page-layout/Map checks passed, including narrow screens, enlarged text, Home docking, legend scrolling, landscape and map controls; Map checks passed again after integrating its title into the legend strip. Flutter analysis and diff whitespace checks passed. Device review remains pending a compatible Android phone.

## Home title emphasis — 2026-10-04

Home's fixed heading now reads `HOME` without the period, using 28 px bold type and 1.2 px letter spacing in the shared compact header. Home is its only current caller. Date, shortcut clearance, scrolling and balance behavior are preserved. All five existing layout checks passed, including narrow screens, enlarged text and Home balance docking. Heading lookups use the new label. Device review remains pending a compatible Android phone.

## Geoapify basemap provider — 2026-10-04

Map replaces public OpenStreetMap tile requests with Geoapify's documented `osm-carto` XYZ PNG endpoint. The user-provided geocoding search URL returns address coordinates and cannot render this tile layer. The existing map UI, markers, traces, saved-log parsing, opt-in location collection, 128 MiB caching and retry behavior remain unchanged. Visible attribution credits Geoapify and OpenStreetMap. No address lookup or inference of missing recorded positions was added.

The supplied key is configured in Git-ignored `config/geoapify.local.json`, passed as `GEOAPIFY_API_KEY` at compilation. An example file and Flutter/Gradle configuration commands are documented. The key never enters preferences, backups, rule snapshots or committed source. A build with no key skips tile requests and explains the missing basemap while retaining log controls and recorded overlays. Client build configuration is not a claim that a binary's key is inaccessible.

Verification: all three focused Map widget tests passed, including provider URL/attribution, missing-key behavior, late location fitting, horizontal legends, right tool rail, narrow/enlarged text, landscape, zoom, selection/trace and failed-tile retry. Flutter analysis reported no issues. One live world-tile request with the supplied key returned HTTP 200, image/png and a valid PNG signature (5,682 bytes). This verifies this request and key, not sustained availability or phone rendering. Compatible-device rendering/offline recovery and profile timings remain unverified; no APK install or phone gestures were performed.

## Restore original picker design and reposition Map controls — 2026-10-04

The current-value action had replaced CupertinoDatePicker with independent wheels and moved Cancel/Confirm into a footer. That exceeded the requested addition of one SVG button. The original native picker is restored, including wheel magnification, localized labels, selection overlay and header actions. Only the SVG current-value action is added below the centered title. The existing picker owns its controllers; the jump reads the public controllers exposed by descendant CupertinoPicker widgets. Date bounds, native leap-day correction, reduced motion and local Confirm/Cancel behavior remain covered.

Map now exposes Fit, trace and zoom as vertically aligned 48 px controls in a middle-right glass rail. Legends are always available in a single horizontal scrolling strip below the upper shortcuts. Timeline and Timeline logs remain between Calendar and Settings. Short viewports constrain the rail and allow vertical scrolling; the lower caption leaves horizontal clearance. This supersedes the three-button toolbar and Map tools drawer described in the earlier entry.

Verification: ten focused picker, Map and shared layout widget checks passed, including actual native date wheel positions, animated/reduced-motion jumps, date bounds, leap-day correction, cancellation, narrow/enlarged text, horizontal legend scrolling, vertical rail alignment, landscape, Map selection/trace, zoom and tile retry. No phone gestures or saved-record changes were performed. Flutter analysis reported no issues; diff whitespace checks passed. The attached phone disconnected during reload. ADB then exposed only an unauthorized device, so reattachment failed and this correction is not yet verified on the phone. The authorized replacement phone is a TECNO LG7n running Android 12/API 31, below the app's Android 15/API 35 minimum; the app is not installed there. Phone review requires a compatible device. No APK was rebuilt or installed.

## Map coverage, compact controls and picker current-value actions — 2026-10-04

Source-confirmed fixes: the first usable locations arriving after an empty result now fit the camera. Cancelled date-range subscriptions cannot replace the current view, and successful stream updates clear query errors even when rows match the previous result. Parsing separates located/unlocated rows once per changed result. Timeline logs includes missing/invalid/stale-location records with an explanation and their stored details; only usable positions remain selectable/plottable. Existing freshness checks are preserved. Numeric `map.total_count` and `map.unlocated_count` have catalog hints, snapshots, compiler validation and RULE_SYNTAX documentation.

The former large floating date/action/category panels are replaced by three 48 px toolbar controls between Calendar and Settings at the same top inset. Timeline and Map tools use shared panels, with date navigation, zoom/Fit, trace and named category filters retained. A compact lower caption reports the date range and location coverage. Shared Chrome adds a themed 94% surface backing under the glass edge, and fixed shortcuts now reuse Chrome, making floating text/icons readable over tiles.

Shared date/time wheels now expose an SVG-only current-value button with tooltip/accessibility label, using the official Lucide rotate-ccw asset and its license with flutter_svg. Public CupertinoPicker controllers animate together over 450 ms; reduced motion jumps immediately. Date limits and leap-day/month lengths clamp safely. Confirm is disabled during motion; Cancel remains available and discards the draft. Header and fixed actions use shared PanelHeading/PanelActions/AppButton after the narrow-text check exposed a crowded header.

Verification: Map record/query/compiler, narrow/landscape toolbar, selection/trace, zoom, tile retry, navigation and shared layout checks passed. The late-arrival regression passed after moving live database writes into the widget test clock; earlier runAsync writes were blocked by a pending fake-clock context write. Picker/nested-sheet checks then passed after the header correction, including actual controller positions, normal/reduced motion, bounds, leap dates and cancellation. The synthetic tile fixture was corrected to valid PNG data. No fake coordinates, permission grants, real rule activation, session ending or phone scrolling was performed.

Phone evidence: an inspected pre-change screenshot showed tiles and recorded dots already loading; aggregate saved-data inspection found missing/stale samples explaining absent markers. This does not establish the cause of an earlier intermittent network failure. Map hot reload succeeded, and the inspected after-capture confirmed the aligned compact toolbar and readable controls. The phone was then on a future week with zero logs, matching the displayed empty state. Network/offline transitions and profile frame timings remain device-review gaps; long-history materialization/clustering remains the unresolved part of F06.

The final picker/SVG update also hot-reloaded successfully (57 libraries), without an APK reinstall. The agent did not operate the phone wheels; their scroll positions and confirm/cancel behavior were verified in widget checks. Final picker/nested-layout checks passed all eight cases after the header fix; the Map/query/navigation cases had passed in the preceding combined run. A final source-only brace correction resolved the remaining lint, and final Flutter analysis reported no issues. Documentation links and diff whitespace checks passed.

## Separate Logs and Syntax builder — 2026-10-04

Settings now gives Activity logs and Syntax builder separate Surface containers. Logs opens `LogsSheet`, a dedicated shared drawer owned by `logs.dart`, without a builder tab or editor state. Syntax builder opens `SyntaxBuilderScreen` as a full-screen Navigator workspace owned by `syntax_builder.dart`, with fixed glass Back control/header, bounded scrolling content and reduced-motion-aware fade transitions. Sessions rule shortcuts and Condition set links use the same workspace, including existing selected-rule lookup. Supporting selectors and permission hints retain the shared drawer. The existing builder body, compiler, saved rules, Run/Stop semantics and native runtime are preserved; no data/schema/rule language change was introduced.

Verification: all seven focused editor/navigation and toast checks passed. The new narrow 320×720, 1.3× text check opens the separate Logs drawer, returns, opens the full-height syntax workspace without PanelContent, and uses Back to restore Settings. Existing completion, enabled-flag persistence and validation checks passed. Flutter analysis found no issues; local documentation links and whitespace checks passed. Phone hot reload succeeded (two libraries reloaded). No APK reinstall, phone scrolling, real rule activation or saved-record change was performed by the agent. Physical workspace appearance remains for user review.

## Shared permission hints — 2026-10-04

Source-confirmed: all Flutter permission entry points use one `PermissionHints` gate and `PermissionHint` panel with feature-specific purpose, benefit, user control and Android instructions. Coverage includes session notifications, transaction receipt notifications, reminder notifications, precise/background location, purchase notification-listener access, exact alarms and overlays. Actions remain fixed around the shared scrolling body. Cancellation does not invoke an OS request; existing grants skip the hint unless managing access. A busy guard prevents stacked requests and resets after native failures. The native cross-app overlay card remains shared with its confirmation renderer.

Running-session state is cached natively before optional notification access, preserving rule context and the saved session when Not now is chosen. Native permission status and settings methods read existing permissions and reject unknown settings targets. No new permission, saved preference, schema, rule field or action was introduced.

Verification: focused permission, overlay reconciliation, rule editor, transaction notification and navigation checks passed. The added AppShell integration check confirms native ID/note caching before the hint, no timer-start call on cancellation, and a still-running SQLite session. Flutter analysis reported no issues. Incremental Gradle `:app:installDebug` compiled Kotlin and installed successfully on the connected Android 16 phone (25 tasks executed, 149 up-to-date), preserving records. Flutter VM-service attachment succeeded and remains connected for hot reload. Actual grant/denial flows for every Android permission and physical animation feel remain manual device-review gaps. The agent did not change grants, end a real session or test phone scrolling.

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

### Today clock synchronization follow-up — 2026-10-04

Status: **resolved in source and automated checks**; installed-phone verification remains pending.

Source-confirmed: reduced motion stopped the analog clock's only scheduled repaint source, while the independent digital timer continued updating. The digital timer also started relative to page creation rather than second boundaries, and Today had no immediate resume refresh. The analog accessibility label refreshed only with ancestor builds.

The implementation now shares sampled device time across the analog accessibility/stepped display, digital time, elapsed duration, date and daily total. Timer wakeups realign to wall-clock seconds; resume immediately samples the current time and updates the date. Reduced motion preserves one-second hand updates without smooth animation; normal motion retains smooth hands. No saved settings, records or native timing contracts change.

Verification: all three focused clock regressions and all four existing layout checks passed; Flutter static analysis reported no issues. The clock regressions cover actual painted-hand changes with both motion settings, second-boundary updates, paused/resumed midnight rollover, backward device-time adjustment and active-session totals. Documentation structure and `git diff --check` were checked. Installed-phone behavior remains unverified; no APK build/install was performed.

These findings originated in the initial documentation audit. They remain unresolved unless explicitly marked resolved below. Recheck their source and add focused regression coverage when implementing a change; follow-up evidence appears at the end of this document.

### F01 — Release signing fallback removed; owner provisioning remains

Resolved in source: Release tasks require external owner credentials and never select debug signing. No release/key was created. Owner keystore provisioning and actual release validation remain separate authorized work.

### F02 — Finance has no immediate closed-Flutter commit

Priority: medium, product expectation gap. `PurchaseListener` queues structured JSON; only `AutomationSync._reconcile` inserts Drift expenses and durable receipts. A payment detected with Flutter closed will not appear as a committed Finance entry or generate its saved confirmation until reconciliation. Accurate documentation resolves the misleading claim, not the implementation gap. A future native/shared database writer requires an explicit migration/concurrency design.

### F03 — Native timer failure handling added

Resolved in source: persisted delivery diagnostics, normal-notification fallback and resume retry preserve saved session ID/start. Physical Android/OEM rejection/fallback delivery remains unverified.

### F04 — Native queue segmented with explicit sample backpressure

Resolved growth-amplification path: durable 200-event preference segments, batched committed-prefix import and reclamation; new periodic samples pause at 5,000 pending events. Essential events are retained without a hard eviction cap. Process-death/disk-failure migration needs device verification.

### F05 — Export and restore share a size policy — resolved

Export and restore share a 128 MiB UTF-8 policy; transaction snapshot plus isolate serialization retains atomicity. A larger export fails explicitly rather than producing an unsupported backup.

### F06 — Map failure recovery and large history need work

Status: **partially resolved, 2026-10-02**. Map tile failures now provide a retry that resets the tile layer and evicts failed images; record-query failures can retry separately. Selected records/dots are preserved during tile retry. Compact controls adapt to short screens, and large badges display `99+` with exact counts retained in accessibility/detail content. The Map widget regression covers retry-triggered image reload, retained selection/trace, a 320 px enlarged-text portrait layout and non-overlapping controls at 640×360; coordinate/query tests also passed (four focused tests total). Static analysis reported no issues. The final widget check verifies zoom activation after map readiness; readiness now rebuilds controls so they cannot remain disabled after initialization.

Remaining: full-year/all-range queries materialize every record and marker group. Unchanged-row skips/cache limits help, but zoom-aware spatial clustering now preserves complete membership; no physical long-history benchmark exists. Real network/offline recovery and native GPS permission/provider failures require phone verification. The user's precise location error was not identified from an error message; the explicit Map locate tool now requests a foreground fix. Profile before adding heavy dependencies; preserve named legends, complete query semantics and truthful sampled traces.

### F07 — Session condition banner is broader than its label — resolved

Priority: low. The banner still links to all saved automation, including notification/Finance-only and paused rules. It now says “Automation rules saved” and directs users to Settings for individual Run/Stop status. It no longer claims that every saved rule is a session condition or that the global location toggle represents every rule. Source checked in `lib/history.dart`; the full widget suite passed.

### F08 — Calendar restores navigation state — resolved in source

Saved selected date/view initialize on remount. Day/week/grid/agenda arithmetic uses calendar components; yearly leap-day movement clamps to the target month. Widget regression covers remount and leap-day navigation; Flutter local-time DST behavior remains a timezone/device gap.

### F09 — Unused direct dependencies removed

Removed animations, cupertino_icons and shared_preferences plus now-unused preferences plugins. Updated glass/Lucide and Play location within compatible versions. Full source/plugin checks cover removal; physical cold-start review remains pending.

### F10 — Restore validation fixed; journal scope documented

Raw log identity/text/epoch/JSON/position values validate before transactional replacement. Logs cover session start/end and Finance insertion/meaningful updates, not every deletion/autosave. This journal scope is explicit; user data-action success feedback remains separate.

## Preserved invariants

Calendar unsupported-operation follow-up — 2026-10-04: source inspection found `agenda` sorting `sessions(selected)` directly. Empty dates return `const []`, so sorting throws an unsupported-operation exception; populated dates also mutated the cached list. The agenda now sorts a copy. The focused page layout regression passed and covers navigating to an empty month; targeted static analysis reported no issues. This source-confirmed cause has not been matched against a phone stack trace: no Android device was connected when checked. No APK build/install or record deletion was performed. Logcat capture instructions are in [Development](DEVELOPMENT.md).

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

#### F11 — Async mutation failure coverage remains incomplete

The listed Finance, formatting, appearance, payment-app and condition callbacks now use guarded feedback; shared tests verify failed/pending commits do not announce success. Individual fault injection for every callback is still a coverage gap, not evidence that these guarded source paths bypass error presentation. The new planner and native batch checks exercise transaction failure/retry explicitly.

#### F12 — Logs stream recovery — resolved

`LogsSheet` in `lib/logs.dart` holds one stream subscription, retains its last loaded rows on failure, and presents explicit Retry. Initial stream errors do not remain skeletons or claim an empty journal. The UI regression injects a read failure after data and verifies retained rows and successful retry; pending-content skeleton behavior retains existing coverage.

#### F13 — Session display formats — resolved

`SessionForm` shares `displayDate` and `clockTime` with existing display surfaces. The UI regression verifies the chosen dd/MM/yyyy date and twelve-hour clock. Source and full-suite evidence also preserve the default twenty-four-hour path.

F06 follow-up: recorded Map stream recovery and tile retry already have passing regressions. This pass adds zoom-aware clusters and set-based selection pruning, preserving complete timeline membership. Full-range materialization and physical long-history performance remain explicit device gaps.

### Historical rechecked risks — superseded by the 2026-10-05 remediation

F01 debug release signing, F02 queued closed-Flutter purchases, F03 swallowed native timer-start failures, F04 unbounded native events, F05 export/restore size disagreement, F06 Map recovery/history cost, F08 Calendar remount/date arithmetic, F09 apparently unused dependencies, and F10 incomplete restore/log validation remain unresolved. No retention policy, database schema, automation language, platform minimum or permission behavior was changed in this pass. `budget_page` compatibility destinations, integer money/currency isolation, transactional reconciliation and commit-before-receipt behavior are retained.

### Fresh automated evidence

- Flutter static analysis: no issues.
- Full Flutter suite: **34 tests passed**, including four new feedback regressions and the current drawer/layout checks.
- Changed documentation's local links and `git diff --check`: passed.
- New feedback coverage checks both motion settings, 320×480 at 2× text with a status-bar inset, replacement without stale-timer dismissal, explicit/automatic dismissal, invalid transaction remaining editable with no insert, and invalid syntax retaining line/column diagnostics without running.
- Tests use in-memory storage and simulated widget/platform inputs. Existing Map tests use memory tiles. Real phone visuals, screen-reader announcements, keyboard/landscape combinations, OS permission flows, background delivery, live payment capture and large-history performance remain device gaps.

## Home naming follow-up — 2026-10-04

Today is now labeled Home in the bottom navigation, its accessibility label and the fixed page heading. The tab uses the Lucide house icon. `TodayScreen`, `today.dart` and `session_page` remain the implementation and automation identifiers; the daily “Today’s total” label retains its date meaning.

Verification: Flutter analysis passed; the existing navigation gesture test and all four layout tests passed. The layout header-date finder now matches full weekday names so a recent-record date cannot make its fixed-header assertion ambiguous. Flutter attached to the connected Android debug app after reopening it to recover VM-service discovery. Hot reload confirmed two updated libraries; the on-device accessibility hierarchy confirmed “Home.” and the Home tab. No APK build/install or data clearing was performed. The debug session stays attached for subsequent design review; this naming check is not a performance or background-lifecycle measurement.

## Home balance docking follow-up — 2026-10-04

The Home balance pill now uses shared liquid-glass `Chrome`. It moves from its centered position to the right edge beneath Settings as Home scrolls, with a 9 logical pixel gap below the 48 px Settings button, and reverses when returning to the top. Scroll updates affect only a transform around repaint-isolated pill content; the page/clock content does not rebuild for each scroll event. An invisible, semantics-excluded layout slot preserves the original space and adapts to wrapped amounts/text. Reduced motion switches directly between positions. No new preferences, stored records or automation fields were introduced; `budget.balance` retains its existing value and meaning.

Verification: Flutter static analysis reported no issues; all eight focused layout and clock checks passed. Documentation links and `git diff --check` passed. Coverage includes intermediate/reversed positions, exact dock spacing/right alignment, return to the original position, a 320 px viewport at 2× text with a top safe inset, one accessible balance label, and reduced-motion docking. The connected Android debug app accepted hot reload; an inspected phone capture confirmed the initial liquid-glass presentation. Android denied ADB swipe injection (`INJECT_EVENTS`), so the on-phone scroll gesture/feel remains for manual review. These are source/layout checks, not profile performance measurements. No APK build/install or record clearing was performed; the debug session remains attached.

## Home live-time caption follow-up — 2026-10-04

Removed the separate daily-total caption and its page-local fold. Home now displays the digital flip clock, an 11 px live device-time line, then the running/ready status. The live-time line updates from the existing second-boundary notifier, includes seconds, and honors 12/24-hour formatting (AM/PM in 12-hour mode). Active flip digits continue to show the current session elapsed time; idle flip digits continue to show device time. Stored sessions and the `session.today_seconds` rule field are unchanged.

Verification: four affected clock/narrow-layout checks passed, followed by the focused active-session check with assertions that the live-time line sits between the flip clock and status. Static analysis passed before the final widget reorder; the final reorder compiled in the passing focused test and phone hot reload. An inspected phone screenshot confirmed the requested order and removal of the daily total. No automated phone scrolling was attempted for this change, following the user's preference for screenshot-only visual review. No APK build/install or saved-record changes were performed.

Home clock-order correction (2026-10-04): after user clarification, the final order is the existing round analog clock, small Current Time line, running/ready status, then the flip clock. This supersedes the order described in the previous follow-up. The focused active-session check passed with vertical-order assertions for all four elements; hot reload succeeded and an inspected phone screenshot confirmed the final arrangement. No phone scrolling, rebuild or record changes were performed.

Home status placement update (2026-10-04): at the user's request, the final order is now round analog clock, small Current Time line, flip clock, then running/ready status. The focused active-session check passed with the updated vertical-order assertions, and a phone screenshot after successful hot reload confirmed the status below the flip digits. No phone scrolling or APK build/install was performed.

## Home clock-out confirmation — 2026-10-04

Home now asks End this session? in the shared 56%/92% drawer before its manual clock-out. The elapsed preview subscribes to the existing time notifier; details inherit the provided primary scroll controller and End session/Keep running remain pinned at the bottom. The header uses the existing liquid-glass icon chrome and theme typography. Cancel, Back or dismissal return without clock-out. Confirmation performs the existing transactional note/end save, guarded against repeated opening/activation; note updates also require the captured session to remain running. Native notification and automation clock-outs are unchanged.

Verification: two new in-memory database/widget checks passed across light/dark and normal/reduced motion. They check opening/closing frames, visible compact actions at 320 px with 1.3× text, expanded live duration, cancellation/Back retaining the active record, explicit confirmation saving one ended record and repeated activation without popping the underlying page. All three existing clock checks passed, and final static analysis found no issues. Changed-document links and git diff whitespace checks passed. Phone hot reload succeeded; the confirmation itself still awaits manual phone review. No phone scrolling, real-session ending by the agent, APK build/install or performance profiling was performed. Shared drawer motion is reused; these checks do not establish profile frame times.


## Universal adaptive sheets and reusable components — 2026-10-04

The user's content-fit/70%/closed contract supersedes the historical 56%/92% drawer. `lib/sheets.dart`, owned by `design.dart`, is the single modal drawer implementation. Default height fits laid-out content up to 70% of the available viewport; expanded is 70%; dragging/swiping down closes it. Short drawers snap between default and expanded, while long content has one open snap at 70%. The shared handle retains tap resizing, accessible increase/decrease and an explicit Close sheet action. Reduced motion and keyboard expansion remain supported.

`PanelContent` owns fixed header/footer slots and the coordinated primary body scrollable. Existing forms, custom selectors, wheels, Home confirmation, Calendar day agenda, Map records, Activity/syntax, managed names, date formats, Finance menus/goal and quick-add use it. Typed DELETE confirmation also uses the universal drawer while preserving its required input. Duplicate local height constraints were removed. Plain body content uses the shared scroll wrapper; lists stay lazy. Measuring laid-out viewport/sliver extents avoids intrinsic measurement or building a second content tree. Default snap height updates when contents change.

`lib/components.dart`, also a design part, centralizes existing opaque Surface cards/containers and liquid-glass Chrome plus shared action buttons, footer groups and headings. Standard Flutter controls retain the central Design.theme styles. Save/Cancel remain pinned; contextual form Delete actions scroll with fields. Two footer actions sit side by side on short/keyboard layouts. No dependency, saved setting, record, schema, rule field or native timing change was introduced.

Verification: Flutter static analysis passed. Shared sheet checks cover short content, 70% expansion, handle drag snapping/swipe dismissal with both motion settings, fixed slots while long lists scroll, and changing short lazy lists into long ones. All 21 affected checks across seven files passed after the corrections, including existing layout, Home confirmation, Map, toast/form validation, syntax editor and clock regressions. The narrow keyboard case initially exposed a footer overflow; the shared responsive action layout and contextual Delete placement resolved it. The drag test was corrected to send continuous movement after crossing the gesture threshold. Hot reload succeeded on the attached Android debug app, and an inspected screenshot confirmed Home remained intact with its running session. No phone scrolling, real-session ending, APK build/install or profile performance measurement was performed; modal appearance and touch feel still require the user's phone review.


## Keyboard navigation and Home note input — 2026-10-04

Source-confirmed: the outer Scaffold and GlassScaffold both used default keyboard resizing, moving the navigation Stack upward. Navigation also used keyboard-sensitive padding. Both scaffold layers now retain full height, navigation uses the persistent viewPadding safe inset, and only the page viewport avoids the keyboard. The bar stays anchored beneath the keyboard while focused content remains scrollable above it. A user follow-up reported that opening was still slow: the initial inset adjustment remained subscribed at the shell, and Home/PageBody rebuilt width-dependent layouts for each height change. Inset updates now stay inside a dedicated viewport; width-dependent layouts cache their content across height-only changes and refresh for width/content/theme changes. Navigation painting, interaction and ticking pause while the keyboard covers it, preserving its geometry.

Home's note listener previously updated SQLite for every keystroke. Each update invalidated the sessions stream and refreshed AppData, the shell and its live automation configuration. Typing now stays local and queues one save after a 400 ms pause. Selection-only changes do not save; active IME composition waits for completion. Blur, page disposal and background transitions flush the draft. Queued writes serialize, target the captured session only while it remains running, and complete before explicit clock-out's transactional note/end save. The note field has a repaint boundary. Errors use the shared error feedback.

Automated checks exercise keyboard opening/closing without moving navigation, input visibility, note batching, selection/composition, blur/page-exit flushing, pending-note clock-out and externally ended-session protection. All 18 affected checks across navigation, note input, shared layout, clock and session confirmation passed after the fixes. Flutter static analysis passed. A dedicated resize check confirmed that four height-only changes do not invoke the layout builder again, while width/theme changes do; keyboard geometry and input visibility also passed. Hot reload succeeded on the attached phone. No phone scrolling, real-session ending or APK build/install was performed. These checks establish saved-data/layout behavior and reduced rebuild work; actual keyboard touch feel and profile frame times remain device-review gaps.

## Global keyboard overlay correction — 2026-10-04

The user's requirement that no components react to keyboard opening supersedes the earlier page avoidance and drawer keyboard expansion. `KeyboardOverlay`, above the Navigator, normalizes keyboard insets to zero and retains persistent safe padding for every page, input, selector and modal. Both shell Scaffolds keep their full height. Android's main activity uses `adjustNothing` to prevent native window resizing/panning. Removed page keyboard padding, navigation visibility switching and drawer automatic keyboard expansion/padding; sheet size and snap positions remain unchanged. Note batching, IME composition handling and draft flushing from the previous fix remain intact.

Verification: 18 targeted widget checks passed across navigation, sheets, Home notes and layouts; static analysis reported no issues. Animated inset steps during opening/closing preserve Home input/navigation rectangles and shared drawer extent, text/numeric field positions and fixed header/footer rectangles. Home's initial focus animation must settle before recording the geometry baseline; an initial check sampled it early and was corrected. Documentation links and diff whitespace checks passed. These are layout/data checks, not physical-device profile frame-time measurements.

Device delivery: incremental Gradle `:app:installDebug` succeeded on the connected Android phone (37 tasks executed, 137 up-to-date). Reopened the installed app; Android window inspection confirmed `adjust=nothing`. An inspected screenshot confirmed Home, its active session and saved note remained intact. No phone scrolling, typing, session ending, uninstall or data clearing was performed. Physical keyboard animation frame times remain unmeasured.
Flutter attachment completed and a hot reload succeeded; the debug session remains attached for review.

## End-session note editing and session island label — 2026-10-04

Home's end-session sheet now includes a multiline Session note field prefilled from the current Home draft, including changes still waiting for autosave. The sheet owns a local controller: editing does not write to SQLite or change the Home note. Keep running, Back and dismissal discard those edits. End session returns the trimmed draft (including an empty note), waits for outstanding Home autosaves, and commits it with clock-out in the existing transaction. The note field reuses central input styling, the shared scrolling body and the global keyboard overlay policy. Live elapsed updates rebuild only the elapsed text.

`SessionService` uses one `Session In progress` label for the standard notification title, HyperIsland builder text and expanded island title. Session kind remains stored; chronometer timing, actions and fallback behavior are unchanged.

Verification: seven focused Home confirmation/note checks passed across normal/reduced motion and light/dark themes, covering current-note prefill, edited-note saving, cancellation/Back discarding edits, repeated confirmation and pending autosave ordering. Phone hot reload accepted the note UI. No actual phone session was ended or note changed by the agent.
Final static analysis found no issues. Incremental Gradle `:app:installDebug` succeeded on the phone, including native Kotlin compilation (28 tasks executed, 146 up-to-date). The installed app was reopened with records preserved. Dynamic Island layout/expanded appearance remains a manual phone-review gap; the compiler confirms all session titles share the requested text.
Device notification inspection confirmed the installed notification title and HyperIsland ticker/chat title all read `Session In progress`. Flutter VM-service attachment completed successfully and remains attached.

## Cross-app session confirmation and permission hint — 2026-10-04

Notification/Dynamic Island Clock out now routes directly to a non-exported translucent native activity using a session-specific activity PendingIntent; HyperIsland action type changes from service (3) to activity (1). Without overlay access, a designed permission card explains Review before ending and You stay in control, with Allow overlay/Keep running. It opens Android settings only on explicit activation. A matching shared Flutter permission sheet in Settings includes status-aware Allow overlay/Manage access and Not now.

Granted access shows a native TYPE_APPLICATION_OVERLAY confirmation with a local editable note, live chronometer, themed rounded surface, fixed actions, coordinated scrolling body, 70% height cap and responsive landscape actions. Permission and confirmation share one native renderer; Flutter in-app sheets continue using panel/PanelContent/AppButton. No Flutter engine or SQLite connection is opened for the cross-app UI. Native dialogs use Android animation scaling and adjustNothing; drafts survive activity recreation. Denial, Back, dismissal and Keep running do not end a session.

End session validates the captured native ID before committing pending ID/end/note and stopping the service. Reconciliation applies note/end transactionally before acknowledgement, including endings queued before automatic-session imports. Ended records ignore replayed notes; legacy pending payloads retain existing notes. The live native boolean device.overlay_allowed is registered for typed rule validation/completion and documented in RULE_SYNTAX. No new modifying rule action or saved setting is introduced.

Verification: native compilation passed. Eighteen affected checks passed across permission/reconciliation, rule language, activity import and Home confirmation. An additional review found the automatic-start replay path also needed to use the common note/end helper; all seven affected import/overlay checks then passed. Initial checks caught a missing Drift query-extension import and two test-only lint issues, which were corrected. Native permission granting, cancellation/Back, cross-app text input and physical animation feel remain device-review gaps; the agent does not grant special access or end the real session.
Final static analysis reported no issues, and the queued-start check passed with an explicit edited-note assertion. Final incremental installDebug succeeded (23 tasks executed, 151 up-to-date), preserving data. Notification extras on the phone confirmed activity action type 1. Android subsequently reported SYSTEM_ALERT_WINDOW allowed; the agent did not grant it. ADB correctly refused direct shell launch of the non-exported confirmation activity, so no export restriction was weakened for a screenshot. Native cross-app UI review remains through the actual notification/island action; no real session was ended by the agent.

## Committed data-action toast feedback — 2026-10-04

Explicit record, planner, automation and settings mutations now acknowledge completion through the existing top pill and shared `DataAction` icons. Saves/updates/deletes are emitted after awaited writes; form notices persist in the root overlay when their sheet closes. Cancelled confirmations and share dismissal stay quiet. Errors keep their alert icon and longer existing duration. Replacement, accessible live-region semantics, dismissal, safe insets and reduced motion are preserved. No database schema, native outbox, permission or rule-language behavior changes.

Verification: all 16 focused checks passed across data feedback, toast, rule editor, Home confirmation and Home note suites. New in-memory tests exercise actual session save/edit/delete, quiet cancellation, and pending/failed-operation feedback without changing phone records. Per-keystroke note autosave and navigation geometry persistence deliberately remain quiet. Application source analysis passed; the final pass found two test-only unnecessary null assertions, which were removed. Phone hot reload succeeded (five libraries). Documentation links and diff whitespace passed. No real phone data action or scrolling was performed; visual action feedback remains for user review.

## Compact toast pill — 2026-10-04

The shared `_Toast` / `top-toast-pill` now uses 10 px padding on every side and a compact 20 px dismiss control, replacing the default 48 px button footprint. Height follows the larger of the message or icons, with no fixed/minimum pill height. Action icons, labelled dismissal, bounded long diagnostics and reduced motion remain. All four existing toast checks passed, covering narrow 2x text, both motion settings, replacement/expiry/dismissal and form/syntax errors. Phone hot reload succeeded; diff whitespace passed.

## Compact log rows — 2026-10-04

Map `_MapLogSheet` and Settings `LogsSheet` now reuse `LogRow` for every log category: title plus full date/time only. Location, category subtitles, raw details and expansion controls are removed from presentation. Located Map rows retain their tracing selection checkboxes; unlocated rows remain visible. No stored log data or query/filter behavior changes. All seven Map/editor checks passed, including unlocated log visibility, grouped located selection, range controls and separate log/workspace navigation. Static analysis of the owning design/screens libraries found no issues; diff whitespace passed. Phone hot reload succeeded. No phone scrolling or saved-record changes were performed.

## Foreground current-location Map marker — 2026-10-04

The cyan You legend and locate rail tool request a fresh fix using the existing native `currentLocation` method and shared permission renderer with contextual Map copy. Opening Map remains GPS-free. The circle has isolated paint-only pulsing (static for reduced motion); camera centering animates for 350 ms with shortest longitude interpolation and stops on user pan. The marker is separate from historical records, not traced/counted, toggles through its legend, and expires after two minutes. Invalid, coarse (over 100 m), stale or future fixes are rejected. No background tracking, saved log or native/schema change. Visibility/sample epoch fields have typed rule completion and snapshot documentation. All 32 unique focused checks passed across Map, sample validation, rule language and shared permission gates. The new cancellation check initially tapped before the sheet entry completed; explicit frame pumping corrected the test. Final affected-source/test analysis found no issues, and documentation links/diff whitespace passed. Initial phone hot reload succeeded (eight libraries); the connection then dropped before final small corrections. Requested incremental `:app:installDebug` succeeded (23 executed, 151 up-to-date), preserving app data. Flutter reattached and hot reload succeeded on the installed app. Real GPS availability, system permission handling and physical pulse/pan feel remain user/device review gaps; no phone scrolling or real location request was performed by the agent.

## Shared expandable log details — 2026-10-05

User refinement adds a drop-down to shared `LogRow`: title/date-time stay compact when collapsed, and every Map/Settings log reveals available metadata on activation. One `logDetails` formatter safely decodes direct/nested positions and optional/malformed details, formats supported integer money, and retains other metadata. Stable record keys preserve row identity; Map checkbox selection is independent. Expansion respects reduced motion. All 13 affected log-row/Map/editor checks passed after removing an unnecessary expansion PageStorageKey that conflicted with selectable text scroll restoration. The new checks cover narrow 1.3x text, both motion settings, expand/collapse, independent trace selection, unlocated logs and malformed optional metadata. Affected-source/test static analysis found no issues; diff whitespace passed. Debug install completed and Flutter reattached; final expansion correction hot reload succeeded. No phone scrolling, real data edits or location request was performed by the agent.

## Map location with precise permission — 2026-10-05

Phone diagnostics confirmed precise/coarse access granted and multiple enabled providers. Source used GPS exclusively whenever enabled, then Map discarded any accuracy over 100 m; the phone reported a GPS estimate above this threshold while other provider fixes existed. This establishes two confirmed failure paths, not a complete recording of the failed user request. New Map-only `MapLocation`/`mapCurrentLocation` considers GPS/network/fused and fresh cache candidates, validates monotonic/wall age, completes once, and cancels bounded requests. Automation request semantics and the unrelated native Automation edit are preserved. Map accepts fresh wider estimates, renders their accuracy halo and centers at a suitable zoom. Disabled system location has a distinct explanation. No continuous/background updates or log writes. All 21 focused Map/sample/rule checks passed, including a 115.2 m estimate rendering its halo and wider zoom. Static analysis found no issues. Native compilation and incremental debug install succeeded (27 executed, 147 up-to-date), preserving data. Permission/provider diagnostics were read from the phone; the agent did not request a new real fix or inject touches. Flutter reattached directly to the device VM and final hot reload succeeded. Actual provider delivery remains for the user's locate-tool review. The new lookup follows Android LocationManager one-shot/cancellation contracts: [Android LocationManager](https://developer.android.com/reference/android/location/LocationManager).
