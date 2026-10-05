# FrekiHub documentation

Current implementation reviewed on **2026-10-02**, starting from commit `f91f75e`. Documentation describes the code and separates tested behavior from device-dependent assumptions.

## Read first

For a new agent session, read [AGENTS.md](../AGENTS.md), [AGENT.md](../AGENT.md), then [App documentation](APP_DOCUMENTATION.md). This establishes the product, source ownership, invariants and known limitations without a repository-wide code read. Read the specialist document for the task, then inspect only the affected source and tests before editing.

## Current references

| Document | Purpose |
| --- | --- |
| [App documentation](APP_DOCUMENTATION.md) | Product behavior, every page, architecture, source map and feature integration |
| [Data reference](DATA_REFERENCE.md) | Tables, money/date rules, preferences, events and backup contracts |
| [Android runtime](ANDROID_RUNTIME.md) | Method channel, services, queues, permissions, notification delivery and closed-app behavior |
| [Development](DEVELOPMENT.md) | Setup, checks, targeted test routing, device testing and troubleshooting |
| [Application audit](APPLICATION_AUDIT.md) | Current evidence, page-by-page review, unresolved findings and verification gaps |
| [Full scan, 2026-10-05](FULL_SCAN_2026-10-05.md) | Whole-app checks, confirmed defects, deprecations and prioritized follow-up |
| [Motion film](MOTION_FILM.md) | Product film storyboard, factual boundaries, original soundtrack and reproducible video source |
| [Rule syntax](../RULE_SYNTAX.md) | User-facing grammar, commands, completion, schedules and limits |
| [Agent guide](../AGENT.md) | Short onboarding and task-to-file routing |
| [Agent instructions](../AGENTS.md) | Automatically discovered repository working rules |

## Historical material

[UI audit history](../UI_AUDIT.md) records earlier passes; its old page counts, pending features and test counts are historical. [Previous README](history/README_PRE_AUDIT_2026-10-02.md) preserves earlier implementation notes. Neither overrides the current references or source.

## Keep this accurate

Update the relevant reference in the same commit as a feature. Update `RULE_SYNTAX.md` whenever grammar, fields, actions, completion or runtime behavior changes. Recheck audit findings before acting on them; a finding is not a fix. Do not present simulated widget tests as device screenshots or performance measurements. Documents provide orientation; affected code remains authoritative for implementation decisions.
