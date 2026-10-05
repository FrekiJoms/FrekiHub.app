# FrekiHub Android runtime

Reviewed on 2026-10-02. Package/namespace: `com.frekihub.freki_hub`. Native code lives under `android/app/src/main/kotlin/com/frekihub/freki_hub/`. This reference describes implemented behavior, not a guarantee of OEM delivery.

The APK requires Android 15 (API 35) or newer because HyperIsland ToolKit 0.4.0 declares that minimum. Supported Xiaomi integration still needs runtime checks; the OS minimum alone does not establish HyperIsland availability.

## Components and storage owners

| Component | Responsibility |
| --- | --- |
| `MainActivity` | Flutter method channel, posting/location access prompts, native settings intents, sound effects, reminder restore on resume |
| `SessionService` | Sticky foreground session chronometer, confirmed clock-out and optional Xiaomi HyperIsland; both notification and island display `Session In progress` |
| `Automation` | Config/snapshot separation, geofences, rule transition ownership, location capture, durable events |
| `ZoneReceiver` | Receives geofence enter/exit and evaluates the owning rule |
| `LocationLogJob` | Persisted approximately fifteen-minute location/recheck and rule-refresh job |
| `AutomationBootReceiver` | Reconfigures after boot/package/time/timezone/exact-alarm access broadcasts |
| `PurchaseListener` | Reads selected apps' payment notifications and queues structured purchases |
| `RuleProgram` | Interprets bounded conditions/actions with native context overrides |
| `RuleNotifications`, `RuleNotificationReceiver` | Alarm state, next occurrence and reminder posting |
| `TransactionNotifications` | Post-commit Finance receipt and tap destination |
| `NotificationSoundSettings` | Notification channel settings and sound observations |

SharedPreferences namespaces are `session`, `automation`, `rule_notifications`, `runtime_events` and bounded `runtime_events_N` segments. Session state stores current ID/start/kind/note and pending native clock-out ID/end. Automation stores config, separate snapshot, legacy queued events during migration, last position/purchase, active rule, inside states and branch/cooldown state. Reminder storage holds each schedule's definition/fingerprint/token/due/sent/limit/exact state. None directly modifies Flutter's Drift tables.

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

The manifest declares internet/network state, fine/coarse/background location, notification posting, exact alarms, boot and foreground/special-use service permissions. The purchase listener is guarded by notification-listener binding permission; geofences use Play services location 21.4.0.

- Location rules require precise location and background access; enabling OS location is separate from permission grants.
- Purchase scanning requires notification-listener access plus explicit package selection. This differs from permission to post FrekiHub notifications.
- Android 13+ notification posting uses its own permission prompt.
- Exact reminder scheduling checks Alarms & reminders access and falls back to inexact alarms if denied/revoked.
- Cross-app session confirmation requires Android Display over other apps access; it is opt-in and checked before each overlay. Android/system or protected surfaces can control whether overlays appear.
- Choosing a channel sound is an OS setting, not the app's interaction sound toggle.
- Viewing historical Map records needs internet for tiles, not a new location permission or tracking toggle. The explicit foreground locate tool uses `mapCurrentLocation` / `MapLocation` after the shared fine-location permission hint. This bounded lookup considers enabled GPS/network/fused providers, validates both monotonic and wall-clock sample age, chooses a fresh fix, and cancels outstanding requests on completion or its 20-second deadline. It distinguishes denied permission, disabled system Location and missing fresh fixes. The `currentLocation` automation/place-picker and periodic automation requests reuse the same GPS/network/fused lookup; location predicates retain their own accuracy/radius and opt-in checks. It neither enables background access nor calls `logLocation`/`recheck`.

Android restricts background foreground-service starts, with specific exemptions such as geofence transitions. The time-only rule path attempts the same timer start but can encounter a platform rejection; failed starts retain session state, record a delivery diagnostic and attempt an ordinary notification fallback; the Flutter shell retries a recorded failure on resume. This is a source-confirmed audit finding, not verified behavior on a specific phone. See [Android foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).

## Session and HyperIsland flow

Flutter starts the native timer with ID/start/day/kind/note. `SessionService` posts notification ID 73 on channel `frekihub_timer`, using the original start time and a count-up chronometer. It returns `START_STICKY` for an active session. The service does not poll the Dart timer every second.

On supported Xiaomi devices, HyperIsland ToolKit 0.4.0 attaches its resources/extras to the same notification, including count-up display and clock-out. Failure falls back to the standard notification and logs a warning. The vendor/system permission and actual HyperOS rendering remain device-dependent.

Notification and Dynamic Island Clock out actions launch the non-exported, translucent `SessionConfirmationActivity` directly through an activity PendingIntent (HyperIsland intent type 1), capturing the session ID. Without overlay access, a themed permission hint explains the purpose and opens Android Display over other apps settings only on Allow overlay. Denial, Back or Keep running leave the timer active. Settings also exposes a shared Flutter permission hint with Allow overlay/Not now or Manage access when already granted.

With `SYSTEM_ALERT_WINDOW` access, a native `TYPE_APPLICATION_OVERLAY` confirmation appears over the current app without starting a Flutter engine or opening SQLite. It has live elapsed time, an editable note, fixed actions and a scrolling body capped at 70% of available screen height. Native cards reuse one renderer for permission and confirmation, honor theme/system animation scaling, and retain keyboard overlay behavior. Note drafts stay local and survive activity recreation; dismissal discards them. Prefill uses the latest reconciled running-session snapshot or the cached native note.

Only End session checks the captured ID, commits `pendingId`/`pendingEnd`/`pendingNote`, removes the active native ID/rule owner and stops the service/notification. A stale or repeated confirmation cannot end a newer session. Flutter applies note/end together only to a still-running matching record, acknowledges after commit and preserves legacy payloads without a note. The same replay-safe helper runs after a queued automatic start is imported. SQLite saving remains deferred while Flutter is closed. Automated rule clock-outs retain their existing behavior.

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

App-owned permission entry points use the shared Flutter hint before requesting session/receipt/reminder notifications, precise/background location, notification-listener purchase access, exact alarms or overlays. `permissionStatus` reports those existing grants; `permissionSettings` accepts only the corresponding known method keys and opens the appropriate Android page. Explicit management still explains the feature when already granted. Cancellation leaves the OS untouched. The native cross-app overlay hint continues using its existing native renderer while Flutter is closed.

`cacheSession` commits the running ID/start/kind/note independently of notification access and rejects an already pending end for the same ID. Flutter caches before the optional notification hint, then starts the foreground timer only after acceptance or when notifications are already allowed. Declining leaves SQLite and native rule session context active; it does not imply a visible notification. No permission is automatically granted.

Channel name: `frekihub/session`. Most payloads are maps or JSON strings; confirm the affected call's types before changing them.

| Methods | Contract |
| --- | --- |
| `cacheSession`, `start`, `stop`, `pending`, `acknowledge` | Cache running context, timer payload, stop, nullable pending ID/end/note/position map and pending-end acknowledgement |
| `permissionStatus`, `permissionSettings` | Existing permission status map; whitelisted permission key to Android settings |
| `automationConfig`, `automationAppState`, `automationReset` | JSON config plus separate snapshot, foreground boolean, clear native automation/reconfigure |
| `automationEvents`, `automationAck`, `automationStatus` | At most 200 queued events per JSON batch, committed-prefix IDs, access plus pending_count/logging_paused/timer_available map |
| `locationPermission`, `backgroundPermission`, `currentLocation` | Precise access prompt, OS app settings, current-position JSON or platform error |
| `notificationPermission`, `notificationApps` | Notification-listener settings, installed launcher app name/package maps |
| `transactionSaved`, `purchaseDestination` | Receipt map → post result, consume `budget` tap destination |
| `receiptNotificationsAllowed`, `receiptNotificationPermission` | Posting status/prompt for saved confirmations |
| `reminderPermission`, `exactReminderPermission`, `reminderStatus` | Posting prompt, exact-access settings/check, enabled/exact map |
| `notificationSoundSettings` | Category string: reminders/transactions/sessions |
| `sound` | clock-in/clock-out/click/transition cue name |

Only the basic timer wrapper tolerates some missing-plugin cases. Android automation methods are not universally implemented on other platforms. Add new native methods with Dart integration, permission/error handling and focused reconciliation checks; do not equate a `result.success` with a successfully committed financial record.

## Durable queue and timer diagnostics — 2026-10-06

`RuntimeEvents` migrates the legacy array into SharedPreferences segments of at most 200 events, committing segments/index before removing the old source. Events commit before tail advancement; an interrupted tail update is recovered by the next queue operation. Acknowledgements advance only a committed prefix. Fully acknowledged segments are deleted after the durable head update; migration cleanup retries after interruption. A partially consumed segment retains at most 199 acknowledged rows until its remaining events commit. Existing IDs and Flutter replay/deduplication remain unchanged.

Flutter drains 200-event batches with a scheduler yield between transactions. A later-batch failure retains that batch for retry and does not undo already committed/acknowledged batches. Essential actions remain durable with no silent eviction. At 5,000 pending events, periodic history samples pause, while live cache/rule evaluation continues; sampling resumes after drainage. `automationStatus`/Syntax builder and native rule fields expose the queue count/pause. This is not a byte cap on essential events or SQLite history.

`SessionService.startSafely` records delivery failures, queues one diagnostic per affected session and attempts a normal chronometer notification that opens the app. `onStartCommand` also handles foreground-promotion failure. Permission and OS channel restrictions can still prevent fallback delivery. Resume retries a recorded failure after reconciliation, preserving the original ID/start. `session.timer_available` means no recorded start failure, not proof of OEM visibility or continuous service survival. Unexpected synchronous method-channel failures return a platform error so Flutter can retain/retry pending work.

Cross-app confirmation captures end time before looking for an optional fresh cached position and commits pending ID/end/note/position before stopping. Both logging and location opt-ins are required; permission denial or no cached fix leaves the end unlocated. Flutter never requests a later location to describe a historical ending. Pending fields clear only after SQLite commit.

Minimum API 35 makes pre-26/29/31/33 branches obsolete; these branches are removed without changing permission gates. Adaptive launcher masking reuses existing artwork. Manifest extraction rules exclude cloud and device-transfer data so runtime queues cannot be transferred/replayed by system backup. OEM delivery, process-death/disk-failure queue migration, permission transitions and launcher appearance still require physical-device checks.

Shared native timer shutdown removes both foreground and ordinary fallback notifications, clears the recorded delivery failure and retains the confirmed/pending record state.
