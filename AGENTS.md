# FrekiHub feature integration

- Preserve the existing Flutter design system, custom selectors, accessibility labels, sound preference and reduced-motion behavior.
- When adding a feature, expose its meaningful observable data in `RuleCatalog.fields` and `RuleCatalog.snapshot` (or the native context in `RuleProgram`). Include type validation and completion hints. Every new saved setting is readable by `data.get("settings.key")` automatically.
- Add new resource targets to `RuleCatalog.targets`; Android receives this catalog through `knownTargets`. Add modifying actions to both the Dart compiler and Android evaluator, scoped to the correct target. Keep unknown targets/actions rejected. Update `RULE_SYNTAX.md`.
- Keep rule source, runtime JSON and live snapshots separate. Never persist snapshots or outbox payloads into the rule configuration. Preserve branch-change deduplication and paused/Run/Stop behavior.
- Verify meaningful changes with relevant compiler, editor or reconciliation checks. Do not build/install an APK unless the user asks for it or connects a device for that purpose.
- Commit and push completed features, as requested by the user.
- Update `RULE_SYNTAX.md` for every syntax change, including commands, fields, validation, completion, scheduling behavior and limits. Keep examples aligned with the compiler and Android runtime in the same feature commit.
