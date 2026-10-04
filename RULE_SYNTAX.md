# FrekiHub rule language

Open Settings → Syntax builder to enter its full-screen workspace, select a saved rule or enable Structured syntax, name the rule, then edit its source. Activity logs open separately. Use the check icon to validate, the play icon to run, and the square icon to stop. Saving structured source leaves it paused. Running saves and enables it. Stopping pauses automation without ending an existing session. The plus icon starts a new rule; other running rules stay enabled.

The compiler produces a bounded JSON program. Android interprets this program; source is never executed as JavaScript.

## System notifications

### Conditional system notifications

Use `notification.show("Title", "Body");` inside an `if` branch under `target == notifications` to send a system notification when conditions match. The title must contain 1–100 characters and the body 1–500 characters. Run requests notification permission. These notifications use the Reminders sound category and are recorded in activity logs when logging is enabled.

```javascript
target == notifications {
  if (time.between("08:00", "09:00") && location.inside() && weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])) {
    notification.show("At the office", "Time to clock in before 09:00");
  }
}
```

Configure this rule's place and radius in the builder. Both the time window and a fresh accurate position inside the radius must match. The weekday condition is optional. Without a fresh position, the rule waits; missing GPS is not treated as leaving the place. The notification posts once when this branch first matches, then again only after another branch/no branch is observed and this branch matches again. Stop/Run permits a new initial match. If notifications are blocked at evaluation time, the branch is still consumed; conditional delivery does not automatically retry. Location/time conditions follow evaluation and location sampling, not exact alarms, so short windows can be missed while the app is closed. Use a `schedule` block for a fixed-time reminder independent of location.

### Scheduled reminders

Schedules run independently of conditional branch changes and work with the app closed. Put them in a `notifications` target block. A rule can also contain separate conditional target blocks.

```javascript
target == notifications {
  schedule("morning_reminder") {
    at("08:00");
    repeat.daily();
    repeat.count(10);
    notification.show("Session reminder", "Time to clock in");
  }
}
```

- `schedule("name") { ... }`: unique identifier within the rule, 1–64 letters/digits/underscores/hyphens, starting with a letter or underscore.
- `at("HH:mm");`: required local 24-hour time. Starts at the next eligible occurrence; a time already passed moves to the next eligible day.
- `repeat.daily();`: repeat each local calendar day at the specified time.
- `repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);`: repeat only on the selected local weekdays. Valid names are `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun`; use `Thu`, not `Thur`. The list must contain at least one day. Duplicate days are combined.
- `repeat.count(10);`: total successful notification deliveries, including the first; integer 1–10,000.
- `repeat.forever();`: unlimited repeats until stopped. Use this instead of `repeat.count()`.
- `notification.show("Title", "Body");`: required title (1–100 characters) and body (1–500 characters).

For a one-time reminder, omit all `repeat.*` commands. For repetition, choose either `repeat.daily()` or `repeat.weekdays([...])`, then exactly one of `repeat.count()` or `repeat.forever()`. Daily and selected-weekday modes cannot be combined. Command order is flexible; duplicate commands are rejected. Up to 16 schedules per rule are supported.

Example: notify at 08:00 Monday through Friday until stopped:

```javascript
target == notifications {
  schedule("workday_reminder") {
    at("08:00");
    repeat.weekdays(["Mon", "Tue", "Wed", "Thu", "Fri"]);
    repeat.forever();
    notification.show("Workday reminder", "Time to clock in");
  }
}
```

Use `repeat.count(10);` instead of `repeat.forever();` for ten successful deliveries across the selected days, not ten calendar days or ten deliveries per weekday. The first eligible occurrence counts as delivery one. Weekend-only repeats use `["Sat", "Sun"]`; all seven days are equivalent to daily repetition. Weekday selection is included in completion.

Run requests notification permission and activates the schedules. Stop/deletion cancels their pending alarms. Stop followed by Run, or changing the rule source, starts a fresh repeat count. Context updates and reopening the app preserve the count. Completed schedules remain saved but inactive. Reminders restore after reboot, app updates, clock/time-zone changes and reopening after force-stop. Missed occurrences are skipped instead of replayed in a burst. Notification permission/channel denial consumes no repeat count; delivery retries at the next eligible local occurrence. An alarm delayed into an excluded weekday is skipped without consuming a delivery, then rescheduled for the next selected day. Local weekday and clock time are preserved across time-zone and daylight-saving changes.

The editor's clock icon opens Android's Alarms & reminders access. With access granted, schedules use precise alarms; otherwise they use Android's inexact fallback and may be delayed. Android battery restrictions and force-stop can prevent delivery; reopening restores the next occurrence. Reminder delivery does not depend on the 15-minute rule evaluation job.

Observable fields: `notifications.exact_allowed` (boolean) and `notifications.schedule_count` (number of active schedules). Sent reminders appear in activity logs when logging is enabled.

Settings → Notification sounds opens a category selector for reminders, saved transactions and running sessions, then Android's sound settings. Android stores these choices per notification channel; they are separate from in-app button sound effects. Running sessions start silent. On Android versions before notification channels, the option opens app notification settings.

Rules can read `notifications.reminder_sound`, `notifications.transaction_sound` and `notifications.session_sound`. Values are sound URI strings or `"silent"` for silent/low-importance categories; fields are sampled during native evaluation and included in completion. Sound selection is controlled by Android settings, not a rule action.

```javascript
target == session_page {
  if (location.inside() && weekday.in(["Mon", "Tue", "Wed", "Thu", "Fri"])) {
    session.clock_in("Work");
    log("Clocked in at office");
  } else if (location.outside()) {
    session.clock_out();
  } else {
    session.continue();
  }
}

target == budget_page {
  if (budget.expenses >= 5000 && budget.currency == "PHP") {
    app.toast("Monthly spending reached PHP 5,000");
  }
}
```

Targets define the action scope, not whether that page is visible. To react to navigation, compare `app.page` with a page target name.

## Targets and fields

Targets: `session_page`, `sessions_page`, `budget_page`, `calendar_page`, `map_page`, `settings_page`, `activity_logs`, `device`, `notifications`, `app`. Several target blocks can share one rule. All fields can be read from any target; modifying actions must match their resource scope.

The Budget tab is now labeled **Finance**. Its existing syntax identifiers remain `budget_page`, `budget.*` and `budget.add_expense(...)`; `app.page` also reports `budget_page` for Finance. Existing rules and saved data continue to work.

**Map** occupies the bottom navigation slot previously used by Calendar. Calendar opens from the fixed upper-left button, opposite Settings. `app.page` reports `map_page` on Map and still reports `calendar_page` on Calendar.

Map fields have completion hints and type checks:

| Field | Type / meaning |
| --- | --- |
| `map.period` | String: `day`, `week`, `month`, `year`, `custom` |
| `map.from`, `map.until` | Strings: local date boundaries (`yyyy-MM-dd`), start inclusive, end exclusive |
| `map.trace_enabled` | Boolean: chronological trace enabled |
| `map.visible_count` | Number: located logs matching timeline and category filters |
| `map.selected_count` | Number: selected logs within those filters |
| `map.center_lat`, `map.center_lng`, `map.zoom` | Numbers: current viewport, refreshed after interaction settles |

```javascript
target == map_page {
  if (data.get("app.page") == "map_page" && data.get("map.visible_count") > 0 && data.get("map.trace_enabled") == true) {
    app.toast("Showing the recorded location trace");
  }
}
```

Map is a read-only view of located records; existing common `log(...)` and `app.toast(...)` actions work under `map_page`. Session/finance mutations still require their own targets. Map context is stored separately from automation source/programs and is the last viewed state when Map is closed. Saved view preferences remain accessible using `data.get("settings.mapPeriod")`, `settings.mapDate`, `settings.mapFrom`, `settings.mapUntil`, and `settings.mapTrace` (preference values are strings).

Location rule radii use **metres**, currently 100–1,000 m in 50 m increments. Map includes sessions, finance, locations and other actions only when recorded coordinates are valid and their sample is fresh relative to the action (at most two minutes old). Category filters also act as the named/color legend. Day/month/year filters use local calendar boundaries; weeks start Monday. Custom dates include the entire final day. Select records in the logs sheet or from a marker; no selection traces all filtered records. Overlapping coordinates group their records in a selectable marker. Dashed traces join chronological samples with straight lines, not road routes or continuous GPS tracking. The map queries the entire selected interval rather than the activity sheet's 1,000-record limit. Basemap tiles need internet; loading Map does not enable background logging, request GPS, or send log titles, financial details or record payloads to the tile provider. Visible attribution and on-demand cached tiles follow OpenStreetMap's tile usage policy.

The authoritative field catalog is `RuleCatalog.fields` in `lib/rule_language.dart`; completion uses it directly. It exposes session activity/type/note/count/duration/today's time; budget income/expenses/savings/net/currency/goal/counts/latest dated transaction details; calendar date/view; appearance/sound; activity count/latest action/title; location enablement/name/coordinates/accuracy/sample age; purchase detection and notification permission; battery, charging, connectivity, media volume, ringer mode and orientation; current page and foreground state.

`budget.balance` is numeric: all-time recorded income minus expenses minus savings, in major units of the selected display currency. It matches Home's balance pill, preserves negative balances and excludes other currencies and unrecorded plans. Unlike `budget.net`, it is not restricted to the current month. It supports completion and numeric comparisons, for example `target == app { if (budget.balance < 100) { app.toast("Balance below 100"); } }`. Android evaluates this field from the last reconciled Flutter snapshot; closed-app queued purchases do not update it until imported.

`data.get("settings.someNewPreference")` reads any exported saved preference. Generic preferences are strings, so compare against double-quoted values. For example `data.get("settings.clockFormat") == "12"`. Internal automation programs and pending receipt/toast transport are excluded. New saved settings automatically appear in completion; new feature data must be registered in the shared catalog/snapshot.

## Conditions

| Syntax | Meaning |
| --- | --- |
| `if (...) { ... }` | First matching branch |
| `else if (...) { ... }` | Additional condition |
| `else { ... }` | Optional fallback |
| `&&`, `\|\|`, `!` | AND, OR, NOT; NOT binds first, then AND, then OR |
| `==`, `!=` | Equality or inequality |
| `>`, `<`, `>=`, `<=` | Numeric comparisons |
| `true`, `false` | Boolean values |
| `location.inside()` / `location.outside()` | Inside/outside this rule's configured place |
| `session.active` | Running session, also accepts `== true` / `!= false` |
| `time.between("08:00", "17:00")` | Local time; inclusive start, exclusive end; overnight ranges supported |
| `weekday.in(["Mon", "Fri"])` | Weekday membership; Mon–Sun |
| `data.get("settings.key") == "value"` | Read a saved setting |

Use `{}` for blocks, `()` for conditions/function calls, `[]` for weekday lists, commas between arguments and `;` after every action. Strings use JSON-style double quotes and escapes. `//` begins a comment. Parentheses can group conditions. Nested if statements, variables, loops, arbitrary JavaScript and arbitrary device APIs are not supported.

## Actions

| Action | Allowed target |
| --- | --- |
| `session.clock_in("OJT")` | `session_page`; OJT, Work, Study, Personal |
| `session.clock_out()` | `session_page`; ends only the session owned by this rule |
| `session.continue()` | `session_page`; preserves the running session |
| `budget.add_expense(100, "PHP", "Food", "Lunch")` | `budget_page`; amount in major currency units |
| `settings.set_theme("dark")` | `settings_page`; light, dark, system |
| `settings.set_sound(true)` | `settings_page` |
| `log("Arrived")` | Any target; requires activity logging to be enabled |
| `app.toast("Message")` | Any target; appears at the top during app reconciliation |
| `notification.show("Title", "Body")` | `notifications`; system notification when a branch matches |

Actions execute once when the matched branch changes, including an initial match after Run. They do not repeat on every check. Stop/Run allows a fresh match. One session action and up to eight total actions are allowed per branch. Source is limited to 8 KB, 16 target blocks, 128 condition nodes and 16 nesting levels; up to 100 saved rules. A short per-target cooldown prevents immediate feedback loops.

App data changes refresh the evaluator while Flutter is active. Foreground reconciliation runs about every 15 seconds. Android periodic jobs are approximately 15 minutes and can be delayed. Time rules are not exact alarms. Device state is sampled during evaluations, not continuously streamed. Location predicates require a fresh accurate location and location permissions; unrelated rules need no GPS. Unknown fields/samples do not satisfy comparisons. Budget/session/log snapshots can be stale while Flutter is closed; queued native actions are committed when the app opens/resumes.

Expense actions use the existing deduplicated transaction import and saved-transaction receipt pipeline. Config snapshots are transported separately and never saved recursively into rule preferences. Legacy visual location rules continue to work.

`device.overlay_allowed` is a boolean live Android field: whether Display over other apps access is granted. Completion exposes it; comparisons require `true` or `false`. For example `target == app { if (data.get("device.overlay_allowed") == false) { app.toast("Enable overlay access in Settings to confirm from Dynamic Island"); } }`. It is read from Android during evaluation, does not grant permission, and is not a persisted Flutter snapshot value.
