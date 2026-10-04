# FrekiHub repository instructions

## Start a new session

Read `AGENT.md`, `docs/APP_DOCUMENTATION.md` and the current findings in `docs/APPLICATION_AUDIT.md` before broad code exploration. Use `docs/README.md` to select the relevant specialist reference, then inspect only affected source/tests before editing. Documentation provides orientation, not permission to edit uninspected code. Check Git status and preserve unrelated changes.

Android is the current target. Six page surfaces are Today, Map, Sessions, Finance, Calendar and Settings; bottom tabs are Today/Map/Sessions/Finance. Calendar and Settings are fixed upper-left/upper-right shortcuts. Logs and the syntax builder are Settings sheets. Preserve `budget_page`, `budget.*`, `BudgetScreen` and native `budget` destinations despite the visible Finance label.

## Feature integration

- Preserve the existing Flutter design system, custom selectors, accessibility labels, sound preference and reduced-motion behavior.
- Use the shared `panel` bottom drawer for record details, forms, selectors and Settings sheets. It has exactly two snap positions (56% compact, 92% expanded), a draggable/accessibility-enabled handle and coordinated content scrolling. Attach the content's primary scrollable to the provided controller; use `scrollable: true` for non-scrollable content. Avoid full-screen container transforms and nested draggable sheets. Preserve keyboard expansion and reduced motion.
- When adding a feature, expose its meaningful observable data in `RuleCatalog.fields` and `RuleCatalog.snapshot` (or the native context in `RuleProgram`). Include type validation and completion hints. Every new saved setting is readable by `data.get("settings.key")` automatically.
- Add new resource targets to `RuleCatalog.targets`; Android receives this catalog through `knownTargets`. Add modifying actions to both the Dart compiler and Android evaluator, scoped to the correct target. Keep unknown targets/actions rejected. Update `RULE_SYNTAX.md`.
- Keep rule source, runtime JSON and live snapshots separate. Never persist snapshots or outbox payloads into the rule configuration. Preserve branch-change deduplication and paused/Run/Stop behavior.
- Verify meaningful changes with relevant compiler, editor or reconciliation checks. Do not build/install an APK unless the user asks for it or connects a device for that purpose.
- The app is in development. For an authorized reinstall on the connected Android device, use the Gradle wrapper's `:app:installDebug` task (`./gradlew installDebug` from `android`, or `./android/gradlew.bat -p android :app:installDebug` on Windows). Reuse incremental outputs; do not clean, uninstall or clear app data unless explicitly requested. Do not create release/store/distribution builds, upload APKs or publish the app without explicit user direction. Local debug APK packaging required by installation is not publishing. Private Git source commits/pushes remain the separate authorized workflow.
- Commit and push completed features, as requested by the user.
- Update `RULE_SYNTAX.md` for every syntax change, including commands, fields, validation, completion, scheduling behavior and limits. Keep examples aligned with the compiler and Android runtime in the same feature commit.

## Data and platform invariants

- SQLite/Drift owns saved records; Android SharedPreferences owns queued runtime events, pending clock-out and schedule state. Preserve transactional import, replay-safe IDs and acknowledgement only after commit. Saved-transaction notifications follow database commit and retry denied delivery without duplicate expenses.
- Store money as integer minor units and finance percentages as basis points; preserve currency isolation, occurrence uniqueness, calendar date keys and epoch session/log instants. Keep the one-running-session index. Manual one-per-day clock-in is a separate existing behavior; do not silently extend or remove it in other paths.
- Location collection/purchase scanning/logging are opt-in. Preserve fresh/accurate samples, rule-owned clock-out and unknown-location waiting behavior. Map reads recorded positions and does not enable tracking, fabricate coordinates or infer road routes.
- Do not describe queued purchases as saved to Finance while Flutter is closed, local reminders as server push, fifteen-minute jobs as exact, or force-stopped processing as guaranteed. Record what requires phone verification.
- Preserve generated Drift ownership: change schema/migrations in `data.dart`, regenerate `data.g.dart` only when needed. Screen parts belong to `screens.dart`; flip clock belongs to `design.dart`. Put imports in the owning library.
- Keep changes bounded. Reuse shared surfaces, choice sheets, wheel pickers, feedback and motion; avoid speculative frameworks, unnecessary dependencies, mirrored tests and repeated checks without new evidence.
- Do not clear records to recover startup, change repository visibility, rewrite shared Git history, add secrets or work on legacy iOS without user direction.

## Documentation and delivery

- Update the relevant documents under `docs/` in every feature commit. `RULE_SYNTAX.md` remains the detailed language reference; `docs/APPLICATION_AUDIT.md` is current findings; `UI_AUDIT.md` and `docs/history` are historical.
- When resolving an audit finding, update its status and evidence in the same commit. Separate confirmed source behavior, automated checks, assumptions and device-dependent observations.
- Keep `AGENTS.md` the canonical operating rules and `AGENT.md` the onboarding/task-routing guide; avoid duplicate conflicting instructions.
- Use relevant checks from `docs/DEVELOPMENT.md`. Documentation-only edits need link/structure checks; do not add app tests for wording. Report the actual verification performed and any remaining device gap.
- Commit and push completed authorized work to the existing private origin. Do not include `.tmp`, personal records, attachments, build artifacts or signing material.
