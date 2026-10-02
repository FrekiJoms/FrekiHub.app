# FrekiHub

Native Flutter app for personal OJT hours and money. Opens directly into Today with no account, server, sample records, or login.

## Included

- **Today:** smooth painted analog clock, persistent running session, haptics, opt-in sounds, notes, offline status, duplicate clock-in protection, recent session details and editing.
- **Calendar:** twelve-month year overview, session / expense / income filters, animated activity markers, swipeable month summaries with charts, quick add, and a draggable day sheet with remembered height.
- **Sessions:** sortable searchable table, month/type/weekday/note filters, adjacent-column resizing with double-tap reset, remembered widths, pinch zoom, panning, date/time previews, editing and confirmed bulk deletion.
- **Budget:** continuous scroll containing net position, elapsed-period ring, safe-to-spend, savings goal, category donut/bars, reorderable/duplicable planner rules, and a combined expected/actual timeline.
- **Settings:** light/dark/system appearance with circular reveal, currency selection, custom categories and payment methods, sound toggle, JSON backup/restore, and typed confirmation for clearing data.
- **Navigation:** four bottom tabs with a central quick-add button for sessions/logs, expenses, income, savings and budget rules; Settings stays fixed in a circular liquid-glass shortcut at the upper right.

## Data and calculations

Drift stores sessions, money entries, rules and preferences in `frekihub.sqlite` in the application documents directory. Generated schema code is checked in. Records use random unique IDs; a database constraint permits only one running session. A clock-in transaction also rejects an existing session for the current local day.

Money uses integer minor units. Decimal input is parsed with integer arithmetic; percentage rules use integer basis points with nearest-minor-unit rounding and BigInt intermediates. Currencies with zero or three minor-unit digits are supported. Changing the selected currency filters totals, calendar money markers and charts to that currency; existing records retain their original denomination. There is no automatic foreign-exchange conversion.

Calendar dates are `YYYY-MM-DD` strings. Session instants use epoch milliseconds for elapsed durations. Recurrence calculations use calendar components and UTC calendar-day differences to avoid daylight-saving drift. Monthly rules retain their anchor day and clamp to the last day of shorter months, including leap February.

Percentage rules use actual income, expenses or net income-minus-expenses in the occurrence's month. Fixed rules multiply amount by quantity. Daily/weekly/monthly/one-off rules respect start/end dates. Safe-to-spend subtracts remaining planned expenses and savings from the selected month's income minus actual expenses and savings; speculative future income is not spendable.

Completed planner occurrences have a unique transaction key, preventing double recording. Deleting that actual transaction makes the expected occurrence actionable again. Skipped/cancelled states are stored per occurrence, preserving future repetitions.

All writes already live on the phone and work offline. Connectivity controls the informational offline message. There is no remote synchronization endpoint or offline-to-server replay in this no-server application.

Backups include every table and setting. Restore validates records, amounts, dates, currencies and settings before replacing data inside a single database transaction. A failed restore rolls back. Export uses the native share/save interface; import uses the native file picker.

## Native running timer

On supported Xiaomi HyperOS devices, the same foreground notification also provides a HyperIsland count-up session timer and clock-out action through HyperIsland ToolKit 0.4.0. The system advances elapsed time from the original clock-in timestamp without polling. Enable FrekiHub's **Show in status bar** notification permission for island support. Unsupported devices or disabled island permissions retain the regular session notification. Clock-out removes both surfaces and uses the existing native-to-Flutter reconciliation.

Android uses a foreground service with a quiet ongoing chronometer and clock-out action. Notification permission is requested on Android 13+. The action saves its exact end time in native preferences even when Flutter is closed. Flutter applies and acknowledges that event on resume; the update is idempotent. Notification denial does not stop local session recording. Force-stopping the app in system settings can remove the notification; the stored session remains.

The iOS project includes a compiled Widget Extension target, ActivityKit attributes, shared App Group entitlements, lock-screen/compact/minimal/expanded views, and a native clock-out intent. Live Activities require a real supported iPhone and enabled system permissions. iOS 17+ supports clock-out in the Live Activity without opening the UI; iOS 16.1/16.2 uses a deep-link fallback that opens the app. Native end events reconcile into Drift on resume. Apple signing must provision the existing App Group for both targets. No push service is required.

## Design and assets

Shared light/dark tokens, monochrome surfaces, subtle textured/vignetted background, pill controls, measured tab-indicator widths, liquid-glass navigation chrome, opaque data cards, and Lucide icons. Motion uses the shared `Cubic(.22, 1, .36, 1)` curve, 40 ms capped stagger offsets, 250 ms control changes, 400/350 ms sheet open/close and 150 ms number changes. Flutter's actual system disable-animations setting bypasses entrances and reveals and stops the analog clock's animation controller. The glass library also bridges accessibility settings; Reduce Transparency is approximated by Increase Contrast by that library.

Geist and Geist Mono are bundled for offline use under OFL-1.1 (`assets/fonts/OFL.txt`). Two Kenney Interface Sounds are bundled as WAV under CC0 (`assets/sounds/LICENSE.txt`), cached on first use by Android SoundPool. Buttons and selections provide light haptics; tabs and modal routes provide transition feedback. Quiet pitched variants of the bundled sounds provide click and transition cues, with a 100 ms limit to prevent overlapping feedback. Sounds default off and can be enabled in Settings. The native icon follows the existing FrekiHub connected-node motif.

## Validation

Flutter static analysis and Android debug APK compilation are the required checks. Android device testing uses the connected physical phone. iOS compilation/signing and device appearance remain unverified on this Windows machine. The iOS property lists and extension/embedding/entitlement references were checked statically.

Android output: `build/app/outputs/flutter-apk/app-debug.apk`.

Run `flutter pub get` before building after generated files have been removed. In particular, `.flutter-plugins-dependencies` must exist before using `flutter build apk --no-pub`; otherwise native plugins can be omitted and database startup can hang with a missing `libdartjni.so`. For normal builds, use `flutter build apk --debug` so Flutter regenerates plugin registration automatically.

In this Windows desktop execution environment, Java's default temp directory caused `Unable to establish loopback connection`. The build succeeds with TEMP/TMP pointing to the workspace `.tmp` directory and `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<absolute workspace .tmp path>`. This is a build-process environment workaround, not an application dependency or SDK change.

Calendar provides Year, Month, Week and Day views. The Sunday-first month grid collapses to the selected week using its drag handle; record dots can switch to labels. Weekly sessions use a 24-hour time grid, with budget entries above it. Daily cards list recorded sessions and transactions across all currencies. Tap a record to edit, or use the calendar add button for the selected date.

Date and time inputs use themed wheel-picker sheets matching the original web app: month/day/year and hour/minute/AM-PM, five visible rows, a highlighted selection band, Cancel/Confirm, and selection feedback. Date limits remain enforced; cancelling leaves the form unchanged.

The Today session timer uses individual split-flap digits with a two-stage 360 ms fold; unchanged digits and colon separators stay still. Reduced-motion settings update digits immediately. This display adds no dependency or per-second sound/haptic cues.

## Optional Android activity and location automation

Settings opens Activity logs or the Syntax builder in a bottom sheet. All collection toggles default off. The builder supports IF inside a named location radius → THEN clock in as OJT/Work/Study/Personal → ELSE keep running or clock out. Select current precise location or enter coordinates, name the place and drag its token into the condition. Radii range from 100–1000 m; up to 100 conditions are supported. Session history has a builder shortcut, and automatic session cards link to their named condition.

Android geofences monitor entry/exit; a persisted JobScheduler job requests a fresh position approximately every 15 minutes and checks missed transitions with an accuracy buffer. Precise location, background “Allow all the time”, enabled system location and Google Play services are required. Android/Xiaomi power management may delay events and jobs; intervals are not exact. Stop collection or automation with the Settings toggles. Location samples older than two minutes are not presented as an action's current location. Force-stop prevents background processing until the app is opened again.

Activity logs store action, timestamp, available location and expandable metadata locally. Session/transaction inserts are logged centrally through SQLite triggers when logging is enabled. Schema version 2 adds activity storage without changing existing session/entry models. Backups include logs and rule settings; restore and clear also reset pending native automation data. The sheet currently shows the newest 1000 logs; full history remains in backups.

Purchase scanning requires Android notification access and an explicit payment-app selection. A local deterministic parser accepts clear paid/purchased/payment-success/debit notifications with one unambiguous PHP/₱/USD/EUR/GBP amount. OTPs, promotions, refunds, failures and ambiguous amounts are skipped. Only structured fields are retained; notification bodies are not stored or sent to an AI/server. Notifications cannot reliably provide purchased item names or the actual merchant location; missing information is labeled unavailable. Duplicate references are idempotent, with an additional short-window guard for repeated notification updates. Parsed purchases queue durably while Flutter is closed, then become regular expense entries in Budget on opening/resuming (or within the foreground polling interval). Imported expenses remain editable. This is not a guarantee of detecting every payment notification format.

Validation: native Kotlin source compilation without Flutter/APK compilation, Flutter static analysis, and focused checks covering schema migration, opt-in logs, purchase-ID deduplication, backup/restore and queued clock-out/clock-in reconciliation. Real-device permission flows, geofence delivery, Xiaomi background behavior and payment-app notification formats still require phone testing.

### Startup and rendering audit

Startup now renders a lightweight, theme-aware orbit loader before preparing glass shaders. Graphics and the SQLite record streams initialize concurrently; stage text reflects actual readiness, and the dashboard enters once with a short fade and lift. There is no minimum splash duration or simulated loading percentage. Reduced motion uses a static mark and immediate entrance. Android launch backgrounds match the light/dark app canvas.

Glass starts at adaptive standard quality; heavier multi-pass shaders load only when needed. Record streams cache each table independently, so preference changes no longer reload sessions, entries and budget rules. Empty automation polling reads only preferences. Theme updates subscribe only to theme/sound preferences, and the Today screen ticks only its timer text rather than rebuilding the page and sorting the full session history each second. The analog clock has its own repaint boundary.

Validated with Flutter analysis and seven focused startup/data, automation and navigation checks. Actual launch latency and frame improvements have not been measured on a connected device. Use a profile build on the phone with Flutter DevTools to compare cold starts and frame times; `FrekiHub.prepareGraphics` is available in the timeline for shader initialization. No APK was built or installed for this change.

### Cold-start recovery

The startup audit found two unbounded waits that could leave the loading screen visible indefinitely: graphics preparation and initial database streams. Graphics now has a six-second recovery deadline and uses solid surfaces when it stalls or fails. Initial record loading has a fifteen-second deadline, then displays a Retry state; late database completion can still recover without clearing records. Database errors appear immediately even while graphics is preparing. These deadlines cap stalled work and do not add a minimum splash duration.

Nine focused checks and Flutter analysis passed, including simulated hung graphics, late shader errors, a delayed database connection, and recovery. ADB reported no connected devices, so the original intermittent Android force-close/reopen failure has not been reproduced on the phone. No APK was rebuilt or installed.
