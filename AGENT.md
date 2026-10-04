# FrekiHub agent entry guide

This is the requested singular `AGENT.md` onboarding guide. **`AGENTS.md` is the canonical instruction file automatically discovered by coding agents.** Keep operating rules there; keep this file focused on orientation and task routing.

## Establish context

1. Read [Repository instructions](AGENTS.md).
2. Read [App documentation](docs/APP_DOCUMENTATION.md).
3. Read [Current audit](docs/APPLICATION_AUDIT.md), especially unresolved findings.
4. Read the specialist reference for your task, using the table below.
5. Check `git status --short`; preserve unrelated work. Inspect the affected implementation and relevant tests before editing. A documentation read replaces broad exploration, not verification of code you change.

## Product facts to retain

- Android-first Flutter app; local SQLite storage; no login, backend, remote sync or AI purchase parser.
- Six main page surfaces: Home, Map, Sessions, Finance, Calendar and Settings. Four bottom tabs; Calendar top-left and Settings top-right. Logs and automation are Settings bottom sheets.
- Quick add is a center-bottom long-press/drag gesture with accessible actions, not a visible plus tab.
- Record editing and Settings sheets use the shared two-position bottom drawer. Follow the drawer contract in [App documentation](docs/APP_DOCUMENTATION.md) and the canonical instructions before introducing a new modal.
- Finance retains `BudgetScreen`, `budget.dart`, `budget_page`, `budget.*` and native receipt destination `budget` for compatibility.
- `Session` stores epoch milliseconds and a date key; money uses integer minor units. Planner rules and automation rules are different resources.
- Flutter commits queued native purchases, settings, toasts and automatic-session records on reconciliation. Do not claim Finance commits immediately while Flutter is closed.
- System reminders are local Android notifications, not server push. Exact-alarm access, notification permission, location permission, system location, Play services and OEM restrictions are separate concerns.
- Structured source compiles into bounded JSON, never JavaScript execution. Source/configuration, live snapshot and native outbox are separate.
- Map reads recorded coordinates; it does not start tracking, infer missing positions or provide road routing.
- No APK build/install unless explicitly requested or a device is connected for testing. Do not extend iOS work unless requested.

## Route a task

| Task | Read | Inspect first |
| --- | --- | --- |
| Navigation, glass, transitions, selectors | App documentation | `main.dart`, `design.dart`, `controls.dart`, `pickers.dart` |
| Clock, session editing, history | App documentation + data reference | `today.dart`, `flip_clock.dart`, `history.dart`, `forms.dart`, `data.dart` |
| Finance math/planner | Data reference | `budget.dart`, `data.dart`, `forms.dart` |
| Calendar | App documentation | `calendar.dart`, `screens.dart`, `data.dart` |
| Map/located records | App documentation + data reference | `map.dart`, `map_records.dart`, `watchMapLogs` in `data.dart` |
| Rule syntax/completion | Rule syntax + Android runtime | `rule_language.dart`, `rule_editor.dart`, `activity.dart`, `RuleProgram.kt` |
| Scheduled/conditional reminders | Rule syntax + Android runtime | `RuleNotifications.kt`, `RuleProgram.kt`, `MainActivity.kt`, manifest |
| Location or purchase capture | Android runtime + data reference | `Automation.kt`, `automation_sync.dart`, `activity.dart` |
| Backup/reset | Data reference + Android runtime | `settings.dart`, `data.dart`, `automation_sync.dart` |
| Startup/loading | Development + audit | `startup.dart`, `main.dart`, `watchAll` in `data.dart` |

Dart paths above are under `lib/`; native paths are under `android/app/src/main/kotlin/com/frekihub/freki_hub/`.

## Finish a task

Use the relevant existing tests listed in [Development](docs/DEVELOPMENT.md). Verify meaningful changes; avoid implementation-mirroring tests and unnecessary repeated runs. Update the feature documentation, syntax reference if applicable, and audit status when resolving a finding. Report what was checked and what still needs a device. Commit and push completed work to the existing private repository, as authorized by the user. Never store secrets, personal records, APKs or temporary verification outputs in documentation commits.
