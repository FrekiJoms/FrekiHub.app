# FrekiHub Android runtime

Reviewed on 2026-10-02. Package/namespace: `com.frekihub.freki_hub`. Native code lives under `android/app/src/main/kotlin/com/frekihub/freki_hub/`. This reference describes implemented behavior, not a guarantee of OEM delivery.

The APK requires Android 15 (API 35) or newer because HyperIsland ToolKit 0.4.0 declares that minimum. Supported Xiaomi integration still needs runtime checks; the OS minimum alone does not establish HyperIsland availability.

## Components and storage owners

| Component | Responsibility |
| --- | --- |
| `MainActivity` | Flutter method channel, posting/location access prompts, native settings intents, sound effects, reminder restore on resume |
| `SessionService` | Sticky foreground session chronometer, clock-out action and optional Xiaomi HyperIsland |
| `Automation` | Config/snapshot separation, geofences, rule transition ownership, location capture, durable events |
| `ZoneReceiver` | Receives geofence enter/exit and evaluates the owning rule |
| `LocationLogJob` | Persisted approximately fifteen-minute location/recheck and rule-refresh job |
| `AutomationBootReceiver` | Reconfigures after boot/package/time/timezone/exact-alarm access broadcasts |
| `PurchaseListener` | Reads selected apps' payment notifications and queues structured purchases |
| `RuleProgram` | Interprets bounded conditions/actions with native context overrides |
| `RuleNotifications`, `RuleNotificationReceiver` | Alarm state, next occurrence and reminder posting |
| `TransactionNotifications` | Post-commit Finance receipt and tap destination |
| `NotificationSoundSettings` | Notification channel settings and sound observations |

SharedPreferences namespaces are `session`, `automation` and `rule_notifications`. Session state stores current ID/start/kind/note and pending native clock-out ID/end. Automation stores config, separate snapshot, queued events, last position/purchase, active rule, inside states and branch/cooldown state. Reminder storage holds each schedule's definition/fingerprint/token/due/sent/limit/exact state. None directly modifies Flutter's Drift tables.

## What works with Flutter closed

| Capability | Implemented outside Flutter | Important qualification |
| --- | --- | --- |
| Elapsed active session | Foreground service chronometer | Persisted start preserves duration; service/notification can be stopped by Android/OEM/user |
| Notification clock-out | Native pending end timestamp | SQLite session update happens on Flutter reconciliation |
| Geofence automation | Play-services receiver + native rule evaluator | Permission, system location, fresh/accurate sample and platform restrictions apply |
| Periodic location log | Persisted JobScheduler job | Approximate interval, not exact tracking; queued until imported |
| Time/device conditional rule | Native refresh during jobs/events/config changes | Sampled evaluation; short time windows can be missed |
| Scheduled reminder | AlarmManager + native receiver | Exact access or inexact fallback; posting/channel permission still required |
| Purchase detection | NotificationListenerService | Only selected apps/recognized formats; queues a structured purchase |
| Finance expense save and receipt | No immediate closed-Flutter database commit | Import/commit/confirmation on opening, resume or foreground reconciliation |
| Rule toast/theme/sound update | Native event only | Flutter displays/applies during reconciliation |

These are **local system notifications**, not FCM/server push. Force-stop is different from leaving the UI or removing it from Recents. Do not promise activity while force-stopped; reopening restores/configures future work. Xiaomi power management and individual permissions require actual device verification.

## Permission boundaries

The manifest declares internet/network state, fine/coarse/background location, notification posting, exact alarms, boot and foreground/special-use service permissions. The purchase listener is guarded by notification-listener binding permission; geofences use Play services location 21.3.0.

- Location rules require precise location and background access; enabling OS location is separate from permission grants.
- Purchase scanning requires notification-listener access plus explicit package selection. This differs from permission to post FrekiHub notifications.
- Android 13+ notification posting uses its own permission prompt.
- Exact reminder scheduling checks Alarms & reminders access and falls back to inexact alarms if denied/revoked.
- Choosing a channel sound is an OS setting, not the app's interaction sound toggle.
- Viewing historical Map records needs internet for tiles, not a new location permission or tracking toggle.

Android restricts background foreground-service starts, with specific exemptions such as geofence transitions. The time-only rule path attempts the same timer start but can encounter a platform rejection; the current catch suppresses the exception after native session state/event creation. This is a source-confirmed audit finding, not verified behavior on a specific phone. See [Android foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).

## Session and HyperIsland flow

Flutter starts the native timer with ID/start/day/kind/note. `SessionService` posts notification ID 73 on channel `frekihub_timer`, using the original start time and a count-up chronometer. It returns `START_STICKY` for an active session. The service does not poll the Dart timer every second.

On supported Xiaomi devices, HyperIsland ToolKit 0.4.0 attaches its resources/extras to the same notification, including count-up display and clock-out. Failure falls back to the standard notification and logs a warning. The vendor/system permission and actual HyperOS rendering remain device-dependent.

Clock-out records `pendingId`/`pendingEnd`, removes the active native ID/rule owner and stops the foreground notification. Flutter reads/applies/acknowledges the pending end after a successful database write. A pending end can exist before an automatic-start event has reached SQLite; keep replay order handling intact.

## Location and rule evaluation

Geofences cover enabled location-dependent rules and monitor enter/exit. Radius is in metres. A periodic job requests/rechecks location when enabled/allowed, while non-location programs can refresh without GPS. On Android 30+, current-location requests have a twenty-second timeout; older versions use a sufficiently fresh last-known sample.

Samples older than two minutes or with accuracy worse than the radius are rejected for location actions. Entry/exit rechecks use an accuracy buffer to reduce boundary oscillation. Missing/stale GPS does not satisfy an outside predicate: location-dependent programs wait rather than treating unknown position as departure. A named place is chosen from configured radii; this is not a reverse-geocoding service.

`RuleProgram` starts from the last Flutter snapshot and overrides live native session, device, notification/sound and location observations. Finance, stored record totals, map view and other Flutter-derived values can be stale while Flutter is closed. Branches are first-match; the selected branch is persisted before actions emit, avoiding snapshot feedback loops. Repeated identical branches do not rerun. A one-second per-target cooldown applies. Stop/Run or relevant program changes permit an initial match again.

Session actions are scoped to `session_page`; `clock_out` ends only a session owned by that rule. Finance expense actions require `budget_page`; settings actions permit only theme/sound under `settings_page`. Common log/toast actions use native outboxes; arbitrary code/APIs are not available. `knownTargets` comes from Dart's catalog; unknown targets are skipped natively and rejected by the compiler.

Android may delay geofence delivery and periodic location work; see [Android geofencing guidance](https://developer.android.com/develop/sensors-and-location/location/geofencing). Do not describe the fifteen-minute job as an exact sampling clock.

## Reminder scheduling and sounds

`RuleNotifications` creates one pending alarm per next occurrence. It computes local clock/weekday matches rather than a fixed millisecond repeat. Definitions are scoped by `ruleId:scheduleName`. Fingerprint/source changes restart counts; context changes preserve them. A token and expected due timestamp reject stale alarm intents.

Daily or selected weekdays can repeat a finite number of successful posts or forever. Stop/deletion cancels pending alarms; exhausted counts remain stored but inactive. Denied posting consumes no count and retries at the next eligible occurrence. Missed occurrences skip rather than produce a burst. Conditional `notification.show` uses branch deduplication and does not retry a consumed branch just because posting was blocked. Full grammar lives in [Rule syntax](../RULE_SYNTAX.md).

With exact access, scheduling uses `setExactAndAllowWhileIdle`; otherwise `setAndAllowWhileIdle`. Resume/boot/time/timezone/package/access changes restore the next local occurrence. Platform alarm policy is documented in [Android alarm scheduling](https://developer.android.com/develop/background-work/services/alarms).

| Category | Channel ID | Default |
| --- | --- | --- |
| Running session | `frekihub_timer` | Low importance, silent |
| Saved transaction | `frekihub_transactions` | Default importance |
| Reminder / conditional notification | `frekihub_rule_reminders` | Default importance |

Channel creation does not replace an existing user's Android sound choice. Sound observations return a URI or `silent`; low-importance channels report silent. Reminders and financial receipts use private visibility. Receipts supply a generic public lock-screen version; do not assume OS settings always hide all metadata.

## Purchase detection and confirmation

`PurchaseListener` ignores FrekiHub's own notifications, disabled scanning and unselected apps. It rejects OTPs, failed/refunded/credited/promotional requests and requires recognized payment/debit success text. One unambiguous PHP/₱/USD/EUR/GBP amount is accepted with validated grouping/decimal syntax. This is regex parsing, not LLM inference.

Deduplication uses package plus reference if available, otherwise notification key/post time, with a two-minute recent-update fingerprint guard. Merchant extraction is best effort; neither item identity nor actual merchant coordinates are guaranteed. A recent device sample may be attached; it is the sampled device position, not a merchant lookup.

The native event queues without writing SQLite. Flutter imports a regular expense and durable pending receipt in one transaction. Confirmation then shows amount, merchant/item, date, source, available location and reference. A tap sends destination `budget`, which opens the Finance bottom tab. Delivery failure retains the receipt for later foreground retry. Replaying the same purchase does not recreate the receipt after it has been successfully posted.

## Method-channel reference

Channel name: `frekihub/session`. Most payloads are maps or JSON strings; confirm the affected call's types before changing them.

| Methods | Contract |
| --- | --- |
| `start`, `stop`, `pending`, `acknowledge` | Timer payload, stop, nullable pending ID/end map and pending-end acknowledgement |
| `automationConfig`, `automationAppState`, `automationReset` | JSON config plus separate snapshot, foreground boolean, clear native automation/reconfigure |
| `automationEvents`, `automationAck`, `automationStatus` | Queued JSON array, list of acknowledged IDs, location/background/listener access map |
| `locationPermission`, `backgroundPermission`, `currentLocation` | Precise access prompt, OS app settings, current-position JSON or platform error |
| `notificationPermission`, `notificationApps` | Notification-listener settings, installed launcher app name/package maps |
| `transactionSaved`, `purchaseDestination` | Receipt map → post result, consume `budget` tap destination |
| `receiptNotificationsAllowed`, `receiptNotificationPermission` | Posting status/prompt for saved confirmations |
| `reminderPermission`, `exactReminderPermission`, `reminderStatus` | Posting prompt, exact-access settings/check, enabled/exact map |
| `notificationSoundSettings` | Category string: reminders/transactions/sessions |
| `sound` | clock-in/clock-out/click/transition cue name |

Only the basic timer wrapper tolerates some missing-plugin cases. Android automation methods are not universally implemented on other platforms. Add new native methods with Dart integration, permission/error handling and focused reconciliation checks; do not equate a `result.success` with a successfully committed financial record.
