# FrekiHub

Native Flutter app for personal OJT hours and money. Opens directly into Today with no account, server, sample records, or login.

## Included

- **Today:** smooth painted analog clock, persistent running session, haptics, opt-in sounds, notes, offline status, duplicate clock-in protection, recent session details and editing.
- **Calendar:** twelve-month year overview, session / expense / income filters, animated activity markers, swipeable month summaries with charts, quick add, and a draggable day sheet with remembered height.
- **Sessions:** sortable searchable table, month/type/weekday/note filters, adjacent-column resizing with double-tap reset, remembered widths, pinch zoom, panning, date/time previews, editing and confirmed bulk deletion.
- **Budget:** continuous scroll containing net position, elapsed-period ring, safe-to-spend, savings goal, category donut/bars, reorderable/duplicable planner rules, and a combined expected/actual timeline.
- **Settings:** light/dark/system appearance with circular reveal, currency selection, custom categories and payment methods, sound toggle, JSON backup/restore, and typed confirmation for clearing data.

## Data and calculations

Drift stores sessions, money entries, rules and preferences in `frekihub.sqlite` in the application documents directory. Generated schema code is checked in. Records use random unique IDs; a database constraint permits only one running session. A clock-in transaction also rejects an existing session for the current local day.

Money uses integer minor units. Decimal input is parsed with integer arithmetic; percentage rules use integer basis points with nearest-minor-unit rounding and BigInt intermediates. Currencies with zero or three minor-unit digits are supported. Changing the selected currency filters totals, calendar money markers and charts to that currency; existing records retain their original denomination. There is no automatic foreign-exchange conversion.

Calendar dates are `YYYY-MM-DD` strings. Session instants use epoch milliseconds for elapsed durations. Recurrence calculations use calendar components and UTC calendar-day differences to avoid daylight-saving drift. Monthly rules retain their anchor day and clamp to the last day of shorter months, including leap February.

Percentage rules use actual income, expenses or net income-minus-expenses in the occurrence's month. Fixed rules multiply amount by quantity. Daily/weekly/monthly/one-off rules respect start/end dates. Safe-to-spend subtracts remaining planned expenses and savings from the selected month's income minus actual expenses and savings; speculative future income is not spendable.

Completed planner occurrences have a unique transaction key, preventing double recording. Deleting that actual transaction makes the expected occurrence actionable again. Skipped/cancelled states are stored per occurrence, preserving future repetitions.

All writes already live on the phone and work offline. Connectivity controls the informational offline message. There is no remote synchronization endpoint or offline-to-server replay in this no-server application.

Backups include every table and setting. Restore validates records, amounts, dates, currencies and settings before replacing data inside a single database transaction. A failed restore rolls back. Export uses the native share/save interface; import uses the native file picker.

## Native running timer

Android uses a foreground service with a quiet ongoing chronometer and clock-out action. Notification permission is requested on Android 13+. The action saves its exact end time in native preferences even when Flutter is closed. Flutter applies and acknowledges that event on resume; the update is idempotent. Notification denial does not stop local session recording. Force-stopping the app in system settings can remove the notification; the stored session remains.

The iOS project includes a compiled Widget Extension target, ActivityKit attributes, shared App Group entitlements, lock-screen/compact/minimal/expanded views, and a native clock-out intent. Live Activities require a real supported iPhone and enabled system permissions. iOS 17+ supports clock-out in the Live Activity without opening the UI; iOS 16.1/16.2 uses a deep-link fallback that opens the app. Native end events reconcile into Drift on resume. Apple signing must provision the existing App Group for both targets. No push service is required.

## Design and assets

Shared light/dark tokens, monochrome surfaces, subtle textured/vignetted background, pill controls, measured tab-indicator widths, liquid-glass navigation chrome, opaque data cards, and Lucide icons. Motion uses the shared `Cubic(.22, 1, .36, 1)` curve, 40 ms capped stagger offsets, 250 ms control changes, 400/350 ms sheet open/close and 150 ms number changes. Flutter's actual system disable-animations setting bypasses entrances and reveals and stops the analog clock's animation controller. The glass library also bridges accessibility settings; Reduce Transparency is approximated by Increase Contrast by that library.

Geist and Geist Mono are bundled for offline use under OFL-1.1 (`assets/fonts/OFL.txt`). Two Kenney Interface Sounds are bundled as WAV under CC0 (`assets/sounds/LICENSE.txt`), loaded once on first use. Sounds default off. The native icon follows the existing FrekiHub connected-node motif.

## Validation

Flutter static analysis and Android debug APK compilation are the required checks. The application has not been launched on a device or simulator. iOS compilation/signing and device appearance remain unverified on this Windows machine. The iOS property lists and extension/embedding/entitlement references were checked statically.

Android output: `build/app/outputs/flutter-apk/app-debug.apk`.

In this Windows desktop execution environment, Java's default temp directory caused `Unable to establish loopback connection`. The build succeeds with TEMP/TMP pointing to the workspace `.tmp` directory and `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<absolute workspace .tmp path>`. This is a build-process environment workaround, not an application dependency or SDK change.
