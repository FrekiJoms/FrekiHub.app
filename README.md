# FrekiHub

FrekiHub is an Android-first Flutter app for session time, personal finance, optional location/activity logs and local automations. It opens into Home without an account or sample records and keeps saved records in SQLite on the phone.

> [!NOTE]
> Core records work locally. Map tiles need internet; Android background features depend on permissions and system restrictions. Purchases detected while Flutter is closed queue until reconciliation. No backend, server push, AI purchase parser or currency conversion is configured.

## Features

- **Home:** analog clock, split-flap session timer, notes, clock-in/out, recent sessions, offline indicator and native running notification with Xiaomi HyperIsland fallback.
- **Map:** full-view map, fixed glass controls, day/week/month/year/custom filters, colored located records, expandable details and chronological sample traces.
- **Sessions:** searchable/sortable phone list or table, custom filters, resizable remembered columns, editing and confirmed bulk deletion.
- **Finance:** income/expenses/savings, currency-specific totals, safe-to-spend, savings goals, charts, recurring planner rules and expected/actual timeline.
- **Calendar:** Year/Month/Week/Day views of saved session and finance records, draggable month collapse and day-sheet quick add.
- **Settings:** appearance, categories/payment methods, interaction sounds, Android notification sounds, logs, conditions, JSON backup/restore and confirmed reset.
- **Automation:** beginner location conditions, typed structured editor with completion/errors, Run/Stop, scoped actions, conditional notifications and local one-time/daily/selected-weekday reminders.

Bottom tabs are **Home, Map, Sessions and Finance**. Calendar sits in the fixed upper-left circle; Settings sits upper-right. Long-press the bottom center for quick add. Finance keeps its existing `budget_page` and `budget.*` rule identifiers for compatibility.

## Technology

Flutter/Dart presentation, Riverpod reactive state, Drift/SQLite data, Kotlin Android services/receivers, liquid-glass chrome, Lucide icons, bundled Geist fonts, flutter_map/OSM tiles and local Android notification/alarm APIs. The exact dependencies are in [pubspec.yaml](pubspec.yaml) and [Android Gradle configuration](android/app/build.gradle.kts).

## Install

1. Use a Flutter SDK compatible with the Dart `^3.13.4` constraint, Java 17 and an Android SDK.
2. Open this workspace and run `flutter doctor -v` to check the toolchain.
3. Run `flutter pub get` to restore declared dependencies and plugin registration.

This repository contains source, not a published app-store installation. Android release currently uses debug signing. Legacy iOS sources are retained but are outside current Android work and were not built in this audit.

## Quick start

Check the source without building an APK:

```powershell
flutter analyze
flutter test --reporter expanded
```

When the user authorizes a build/device test, select a connected device from `flutter devices` and run `flutter run -d DEVICE_ID`. Replace `DEVICE_ID` with the listed phone ID. Do not rebuild/install solely for documentation or disconnected-device work.

The app starts with empty local records. Create a session or finance entry first. Logging, location conditions and purchase scanning are opt-in under Settings. Notification sounds are separate from button effects; Android permission/channel settings still control delivery.

## Documentation

The complete references are indexed in [Documentation](docs/README.md). New agent sessions should start with [Agent instructions](AGENTS.md), [Agent entry guide](AGENT.md) and [App documentation](docs/APP_DOCUMENTATION.md), then read only the specialist reference and source needed for the task.

- [Data reference](docs/DATA_REFERENCE.md): tables, money/dates, preferences, event IDs and backups.
- [Android runtime](docs/ANDROID_RUNTIME.md): native components, method channel, queues, permissions and notification behavior.
- [Rule syntax](RULE_SYNTAX.md): supported commands/fields, completion, schedules and limits.
- [Development](docs/DEVELOPMENT.md): setup, targeted checks, device workflow and troubleshooting.
- [Application audit](docs/APPLICATION_AUDIT.md): current evidence and unresolved findings.

Earlier descriptions are preserved in [Previous README](docs/history/README_PRE_AUDIT_2026-10-02.md) and [UI audit history](UI_AUDIT.md). Historical test counts and pending features do not override current behavior.

## Verification status

The 2026-10-02 whole-app source audit passed static analysis and **29 Flutter tests**. No APK was built/installed in that pass. Actual phone appearance, frame timings, cold-reopen behavior, HyperOS rendering and background permission/delivery paths remain device-verification work. See the audit for unresolved issues rather than treating passing tests as a bug-free guarantee.

## Contributing

Read the [Development guide](docs/DEVELOPMENT.md), preserve the existing design/data/runtime contracts and update documentation with each feature. Add meaningful checks for changed behavior; avoid redundant tests and speculative frameworks. The user has requested commit/push after completed features to the existing private repository. Do not change visibility, commit personal records or include signing secrets/build outputs.

## Asset licenses

Bundled Geist fonts use [OFL-1.1](assets/fonts/OFL.txt). Bundled Kenney interface sounds use [CC0](assets/sounds/LICENSE.txt). These asset licenses do not establish a project-wide application source license; no root application license is currently declared.
