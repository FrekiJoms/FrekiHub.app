# FrekiHub data reference

Reviewed on 2026-10-02. Schema/calculations live in `lib/data.dart`; `lib/data.g.dart` is generated. Android event transport and Flutter import are separate from this database.

## Storage and schema

Drift opens the local database named `frekihub`, schema version **2**. Version 2 adds a manually created `activity_logs` table and triggers. `sessions`, `entries`, `rules` and `preferences` are typed Drift tables. Keep raw-table creation/migration, export/restore and reactive notifications aligned when changing activity storage.

| Table | Columns / representation | Contract |
| --- | --- | --- |
| `sessions` | `id`, `day`, `kind`, `started`, nullable `ended`, `note` | ID primary key; timestamps epoch ms; `ended == null` means running |
| `entries` | `id`, `day`, `kind`, `amount`, `currency`, `category`, `method`, `note`, nullable `occurrence` | Integer minor units; occurrence has a unique constraint |
| `rules` | `id`, `title`, `kind`, `amount`, `currency`, `quantity`, `basis`, `cadence`, `start`, nullable `finish`, `category`, `method`, `position` | Finance planner rules, not automation programs |
| `preferences` | `key`, `value` | Strings; complex values encode JSON |
| `activity_logs` | `id`, `time`, `action`, `title`, `location`, `details` | Raw SQL table; `details` is JSON text; time index supports ordered/range reads |

`one_running_session` is a partial unique index over sessions with null end. Keep it when migrating/recreating the schema. IDs are generated locally. Foreign-key relationships between log details and source records are not enforced; a log can remain after the related session/entry is edited or deleted.

Manual `clockIn` additionally rejects another session assigned to today. Forms and automatic imports do not share that one-per-day check. `clockOut` updates only a matching session whose end is still null, making repeated end events harmless.

## Money and finance projections

`currencyDigits` declares supported currency precision. `parseMoney` validates decimal text and uses integer arithmetic rather than floating-point currency storage. `money` formats minor units for display. For two-decimal currency, 12,345 represents 123.45; zero/three-decimal currencies use their declared scale.

Selected currency filters `AppData.total`, Finance charts and projections. Calendar agendas can show records in their original currencies. No conversion rate is applied anywhere. Never sum different currencies into a misleading total.

For planner rules, fixed `amount` is minor units; percentage `amount` is basis points (`10000 == 100%`). Quantity multiplies both fixed and percentage results. The form enforces positive value, quantity 1–100,000, percentage no greater than 100%, valid dates and the amount-times-quantity bound. Restore permits non-negative stored values and validates its own bounds.

Percentage bases are income, expenses or `max(0, income − expenses)` for the occurrence month. Calculation uses BigInt intermediates and nearest-minor-unit rounding. Recurrence supports once/daily/weekly/monthly; monthly uses the anchor day clamped to the month's final day. The public `project` interval includes both endpoints, unlike Map's exclusive-end SQL interval.

Occurrence identity is `ruleId:yyyy-MM-dd`. A transaction's unique `occurrence` marks completion. `status:OCCURRENCE` stores planned/skipped/cancelled choices; a real linked transaction overrides the display to complete. Projection itself does not automatically insert transactions.

Finance net is actual income minus expenses minus savings. Safe-to-spend excludes remaining planned non-income commitments dated today or later within the selected period and clamps at zero. Savings goals are per currency; saved progress uses recorded savings in that currency.

`AppData.balance` uses recorded income minus expenses minus savings across all dates, filtered to the selected currency, in integer minor units. Today's pill formats it with `money`; the rule snapshot exposes `budget.balance` in major units. Negative balances are retained; future plans and other currencies are excluded.

## Dates and timestamps

- Record day/start/finish keys are local calendar strings `yyyy-MM-dd`.
- Session start/end, log event time and location sample time are epoch milliseconds.
- Session duration subtracts instants; do not derive it from a formatted clock string.
- Weekly finance recurrence uses UTC calendar-day differences, avoiding fixed-duration DST drift.
- Calendar grid weeks start Sunday; Map range weeks start Monday.
- Reminder next-occurrence calculations use Android local `Calendar`, selected weekdays and local clock time.
- Map range start is inclusive and end exclusive. Custom final dates expand to the following local midnight.

Do not apply a blanket 24-hour millisecond offset when implementing calendar recurrences. Check any new week/date navigation behavior around daylight-saving transitions, even though the current workspace timezone is Asia/Manila.

## Activity logging and location provenance

SQLite triggers run only when `activityLogging == "true"`. They record session insert, the first null-to-ended transition and entry insert. They do not cover every edit/delete, selector tap or setting change. Titles begin with actions such as Clocked in, Clocked out, Purchased, Received income and Saved money.

Triggers retain a nested `position` JSON string from `locationDetails`. Human-readable location is available only if the cached sample is fresh relative to the trigger's current clock. A backdated record must not be assigned today's sample without checking its actual event timestamp.

Native events can put `lat`, `lng`, `accuracy` and `locationTime` directly in their JSON. `MapRecord.parse` accepts direct or nested position maps/JSON, rejects invalid coordinates and enforces sample freshness relative to event time where provided. It never substitutes a rule's configured center for an actual recorded sample.

`watchActivityLogs` reads the newest 1,000 records. `watchMapLogs(from, until)` reads all saved records in that interval in ascending `time, id` order. Export reads full history. Neither the database nor native event queue has a defined retention policy.

`addActivity` deduplicates by event ID, writes the event as `details`, updates `logRevision` and maintains activity count/latest metadata. Raw log watchers use preference/session/entry table invalidations; direct raw writes must preserve a notification path. Structured-rule preference reads also derive current log metadata.

## Preference families

The exact saved keys are visible in `pref` call sites. These are the important families; absent values use defaults rather than implying enabled collection.

| Keys | Purpose / default |
| --- | --- |
| `theme`, `sound` | System appearance; in-app sounds off |
| `currency`, `categories`, `methods` | PHP default; JSON lists with fallback category/payment options |
| `dateFormat`, `clockFormat`, `columnWidths` | Session display formats and six table widths |
| `savingsGoal:CURRENCY` | Minor-unit goal for that currency |
| `status:ruleId:day` | Finance occurrence state |
| `activityLogging`, `locationEnabled`, `purchaseScanning` | Opt-in booleans stored as strings |
| `automation` | JSON configuration: saved visual/structured rules and selected payment apps |
| `locationName`, `locationDetails`, `locationSampleTime` | Cached imported position label/payload/time |
| `logRevision`, `activityCount`, `lastActivityAction`, `lastActivityTitle` | Log refresh/observable metadata |
| `calendarSelected`, `calendarView`, `dayPanel` | Exported calendar selection/view; legacy day-sheet extent retained for backup compatibility, no longer used by the shared drawer |
| `mapPeriod`, `mapDate`, `mapFrom`, `mapUntil`, `mapTrace` | Saved map view preferences |
| `mapContext` | Separately encoded last viewed map runtime observations |
| `currentPage` | Current target string for rule navigation conditions |
| `purchaseNotice:EVENT_ID` | Pending post-commit receipt JSON; remove after posting succeeds |
| `ruleToast:EVENT_ID` | Pending Flutter toast; consume during shell reconciliation |

`RuleCatalog.snapshot` exports generic saved preferences under `settings.KEY` as strings, excluding `automation`, receipt payloads and toast outboxes. Explicit fields such as `settings.sound` override that generic representation with their validated type. Register meaningful new feature fields/types/hints explicitly; generic string access is not a substitute for a clear observable API.

`mapContext` is runtime observation state, not automation source/program configuration. Keep it separate and avoid recursive snapshot/config storage. See [Rule syntax](../RULE_SYNTAX.md) for the public field semantics.

## Native event contract and reconciliation

An event has `id`, `time`, `action`, human-readable `title`, optional `location` and action-specific metadata. Android persists a JSON array in automation SharedPreferences until Flutter acknowledges IDs. New events must be replay-safe; native emission can precede a Flutter commit by hours or days.

| Action | Import behavior / extra fields |
| --- | --- |
| `auto_clock_in` | Inserts missing session if no session is running; `sessionId`, `started`, `kind`, rule/place metadata |
| `auto_clock_out` | Ends only matching still-running session at event time; `sessionId` |
| `purchase` | Parses positive major-unit amount, inserts expense using event ID/occurrence and saves a receipt; `amount`, `currency`, `merchant`, `source` or `package`, optional reference/category |
| `rule_setting` | Applies only allowed `sound`/`theme` values |
| `rule_toast` | Stores a pending top toast for Flutter consumption |
| `location`, `location_exit`, `custom_log`, `error` | Log/metadata handling; no invented session or transaction |
| `scheduled_notification`, `conditional_notification` | Records successful native reminder action when logging is enabled during import |

Native automatic session IDs can be pending before SQLite has the session. Reconciliation handles a notification clock-out arriving around that start. Imported purchase IDs and unique occurrences prevent duplicate expenses. Generic insert logs are replaced with native event logs to preserve precise timestamps and position provenance. Logging may be off without disabling a purchase or session action.

Cross-app confirmed endings add an optional `pendingNote` beside native `pendingId`/`pendingEnd`. Flutter writes that note only to the captured still-running record and ends it in the same transaction; replay cannot alter an already-ended note. Legacy payloads without a note preserve existing text. Queued automatic starts receive the note/end after import. All pending fields clear only after database commit.

Import executes inside a database transaction. Only after commit does Flutter post receipts and acknowledge events/pending clock-out. A failed import must not acknowledge data as saved. Receipt delivery failure leaves `purchaseNotice:*` for retry; it does not undo the saved entry. Do not move confirmation before commit.

## Backup, restore and reset

The current JSON envelope is `format: "frekihub"`, `version: 1`, plus `sessions`, `entries`, `rules`, `preferences` and `activityLogs`. Database schema version and backup envelope version are different concepts. Legacy backups without `activityLogs` restore an empty log list.

Export includes all preferences, including any pending receipt/toast records, and full logs. Native unimported events and Android-owned channel sounds are not part of the SQLite export. Therefore export is not guaranteed to capture everything queued in Android while Flutter has not reconciled.

Restore validates typed records, supported currency/settings, canonical dates, maximum amounts, rule bounds and one-running-session state before replacing data in one transaction. Raw activity log rows rely partly on SQL constraints; their JSON content is not comprehensively schema-validated. Failure rolls back. The Settings restore path additionally resets native state and reconfigures automation. Calling `db.restore` alone does not perform all platform cleanup.

The UI accepts at most 20 MiB; export has no corresponding size limit. This mismatch is an unresolved audit finding. Native pending events/schedule progress are not a portable backup contract. Notification channel choices remain under Android ownership.

Clearing records or uninstalling removes local application data. Backups contain sensitive financial/location information as plain JSON; the application does not add database/backup encryption or a cloud copy.
