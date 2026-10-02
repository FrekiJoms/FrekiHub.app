# FrekiHub rule language

Open Settings → Conditions & automation, select a saved rule or enable Structured syntax, name the rule, then edit its source. Use the check icon to validate, the play icon to run, and the square icon to stop. Saving structured source leaves it paused. Running saves and enables it. Stopping pauses automation without ending an existing session. The plus icon starts a new rule; other running rules stay enabled.

The compiler produces a bounded JSON program. Android interprets this program; source is never executed as JavaScript.

## Scheduled system notifications

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
- `at("HH:mm");`: required local 24-hour time. Starts at the next occurrence; a time already passed starts tomorrow.
- `repeat.daily();`: repeat each local calendar day at the specified time.
- `repeat.count(10);`: total successful notification deliveries, including the first; integer 1–10,000.
- `repeat.forever();`: unlimited repeats until stopped. Use this instead of `repeat.count()`.
- `notification.show("Title", "Body");`: required title (1–100 characters) and body (1–500 characters).

For a one-time reminder, omit all `repeat.*` commands. For daily repetition, specify `repeat.daily()` and exactly one of `repeat.count()` or `repeat.forever()`. Command order is flexible; duplicate commands are rejected. Up to 16 schedules per rule are supported.

Run requests notification permission and activates the schedules. Stop/deletion cancels their pending alarms. Stop followed by Run, or changing the rule source, starts a fresh repeat count. Context updates and reopening the app preserve the count. Completed schedules remain saved but inactive. Reminders restore after reboot, app updates, clock/time-zone changes and reopening after force-stop. Missed occurrences are skipped instead of replayed in a burst. Notification permission/channel denial consumes no repeat count; delivery retries at the next local occurrence.

The editor's clock icon opens Android's Alarms & reminders access. With access granted, schedules use precise alarms; otherwise they use Android's inexact fallback and may be delayed. Android battery restrictions and force-stop can prevent delivery; reopening restores the next occurrence. Reminder delivery does not depend on the 15-minute rule evaluation job.

Observable fields: `notifications.exact_allowed` (boolean) and `notifications.schedule_count` (number of active schedules). Sent reminders appear in activity logs when logging is enabled.

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

Targets: `session_page`, `sessions_page`, `budget_page`, `calendar_page`, `settings_page`, `activity_logs`, `device`, `notifications`, `app`. Several target blocks can share one rule. All fields can be read from any target; modifying actions must match their resource scope.

The authoritative field catalog is `RuleCatalog.fields` in `lib/rule_language.dart`; completion uses it directly. It exposes session activity/type/note/count/duration/today's time; budget income/expenses/savings/net/currency/goal/counts/latest dated transaction details; calendar date/view; appearance/sound; activity count/latest action/title; location enablement/name/coordinates/accuracy/sample age; purchase detection and notification permission; battery, charging, connectivity, media volume, ringer mode and orientation; current page and foreground state.

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

Actions execute once when the matched branch changes, including an initial match after Run. They do not repeat on every check. Stop/Run allows a fresh match. One session action and up to eight total actions are allowed per branch. Source is limited to 8 KB, 16 target blocks, 128 condition nodes and 16 nesting levels; up to 100 saved rules. A short per-target cooldown prevents immediate feedback loops.

App data changes refresh the evaluator while Flutter is active. Foreground reconciliation runs about every 15 seconds. Android periodic jobs are approximately 15 minutes and can be delayed. Time rules are not exact alarms. Device state is sampled during evaluations, not continuously streamed. Location predicates require a fresh accurate location and location permissions; unrelated rules need no GPS. Unknown fields/samples do not satisfy comparisons. Budget/session/log snapshots can be stale while Flutter is closed; queued native actions are committed when the app opens/resumes.

Expense actions use the existing deduplicated transaction import and saved-transaction receipt pipeline. Config snapshots are transported separately and never saved recursively into rule preferences. Legacy visual location rules continue to work.
