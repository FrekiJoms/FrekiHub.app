# FrekiHub app documentation

This is the current product and implementation reference, reviewed on 2026-10-02 from `f91f75e`. It is written for maintainers and new agent sessions. Follow [Agent instructions](../AGENTS.md) when making changes.

## Product and scope

FrekiHub records session time, personal income/expenses/savings, recurring finance plans, optional activity/location logs and local Android automations. It opens into Home without an account, server connection or sample records. Core storage and calculations work locally. The basemap requires network tiles; there is no remote record synchronization or currency conversion.

The current work targets Android 15 (API 35) or newer, matching the minimum declared by HyperIsland ToolKit 0.4.0, including Xiaomi HyperOS integration where supported. Legacy iOS ActivityKit sources remain in the repository but were not built or tested in this audit. Their presence does not imply Android location, purchase or reminder features work on iOS.

## Pages and navigation

`AppShell` manages six page surfaces inside one `/` GoRouter route. Page indices are implementation details; target strings are automation compatibility contracts.

| Index | Visible name | Entry | Widget / target |
| --- | --- | --- | --- |
| 0 | Home | Bottom tab | `TodayScreen` / `session_page` |
| 1 | Map | Bottom tab | `MapScreen` / `map_page` |
| 2 | Sessions | Bottom tab | `HistoryScreen` / `sessions_page` |
| 3 | Finance | Bottom tab | `BudgetScreen` / `budget_page` |
| 4 | Settings | Fixed upper-right circle | `SettingsScreen` / `settings_page` |
| 5 | Calendar | Fixed upper-left circle | `CalendarScreen` / `calendar_page` |

Home (formerly Today) uses the Lucide house icon in the bottom tab and the heading “Home.”. Its implementation remains `TodayScreen` in `today.dart`, with the existing `session_page` automation target.

Calendar and Settings toggle back to the last bottom tab. Navigation uses direction-aware slide/fade transitions and an elastic selected pill. Outgoing pages ignore touches and pause tickers during the transition. This is an `AnimatedSwitcher`, not an always-mounted tab stack; screen-local selections may reset on leaving a page. Persisted preferences and database records survive. Do not assume Android Back represents a stack of tab changes.

Hold the bottom center to reveal quick-add actions, drag over an action and release to choose it; releasing outside cancels. Actions cover session/log entry, expense, income, savings and finance planner rules. The shared navigation also exposes accessible quick-add actions. There is no central plus tab.

## Home and active sessions

Home shows the analog clock, a split-flap elapsed timer, session note input, clock-in/out control, small live-time caption, recent records and an informational offline state. Timer digits update separately from the page; unchanged digits do not animate. The analog clock has a repaint boundary. Reduced motion suppresses smooth hand/flip transitions while keeping the clock updating once per second. Home samples local device time at second boundaries and immediately on app resume; its date, accessibility time label, elapsed display and live-time caption follow the same sample. Normal-motion analog hands continue moving smoothly between samples. Time changes are sampled again rather than accumulated as timer counts.

Home's compact centered heading and date stay fixed between the floating Calendar/Settings shortcuts, outside the scrolling content viewport. Its fitted liquid-glass balance pill begins centered above the clock. As Home scrolls down, the pill follows a smooth scroll-driven path to the upper-right corner, right-aligned with Settings and 9 logical pixels below its 48 px button; scrolling back to the top returns it to the original position. Reduced motion switches positions without the travel animation. Only the pill transform updates on scroll, with its painted content in a repaint boundary and its original space reserved in the list. One balance label remains exposed to accessibility. The pill shows all-time recorded income minus expenses and savings in the selected currency, with the same value exposed as `budget.balance`. While idle, the flip display shows live device time including seconds and respects the 12/24-hour preference; during a session it shows elapsed time. The session card order is round analog clock, small 11 px live device-time line, digital flip display, then the running/ready status. It updates from the same second-boundary sample and follows the 12/24-hour preference, including AM/PM in 12-hour mode. The former daily-total and clock-in timestamp captions are removed. Page-top add buttons are removed; the bottom long-press quick-add gesture and context-specific inline add actions remain available.

The top 28 px of Home's scrolling viewport fades to transparency beneath the fixed header. This uses one static alpha mask, without an animation controller or blur; it does not intercept touches or affect the header. The former bottom privacy reminder card is removed.

Manual clock-in creates an OJT session through `AppDatabase.clockIn`. It rejects an existing running session or any session already assigned to today's date. This is stricter than the database's one-running-session constraint: manual forms and native automatic imports use other write paths and can create multiple completed records on one day. Preserve that distinction or deliberately change it across paths.

Home's manual Clock out action opens an “End this session?” confirmation in the shared adaptive drawer. It previews live elapsed time, session type and the formatted start time. End session and Keep running remain fixed at the bottom; details use the drawer's primary scroll controller. Keep running, Back and barrier dismissal preserve the active session. Only explicit confirmation commits the existing note/clock-out transaction. Repeated opening/confirmation is guarded. Opening/closing reuse the shared 250/150 ms motion and reduced-motion behavior. Native notification and automation clock-outs retain their existing behavior.

The timestamp is authoritative for duration; a ticking Flutter widget is not the source of elapsed time. Android's foreground chronometer uses the original start instant. A system notification clock-out stores an exact pending end instant and Flutter reconciles it later. Automatic records use notes beginning `Automatic · PLACE`; visible condition links currently derive the location name from that note, so changing the note can remove the shortcut.

Session forms support OJT, Work, Study and Personal, editable date/start/end/note, wheel time/date input and saved/running records. Opening a session uses the shared bottom drawer rather than a full-screen container transform. End must follow start; a running session cannot start in the future. There is no account-level attendance synchronization.

## Sessions

Sessions defaults to a phone list with an optional table. Search includes date, type, note and formatted date. Expandable filters cover month, type, weekday and note presence; sorting exposes column and direction. Stable timestamp/ID tie-breaks avoid arbitrary equal-value order.

The list has its own bounded vertical scrolling viewport. The table uses separate horizontal scrolling, six columns, remembered widths, adjacent-column resizing and double-tap width reset. It does not currently use pinch-to-zoom. Bulk deletion is confirmed; deleted IDs and invalid filter values are pruned. Date/time formatting preferences affect session display and previews.

## Finance

Finance shows selected-month income, expenses, savings, net, safe-to-spend, elapsed-month progress, savings goal, category charts, planner rules and a combined expected/actual timeline. All totals and finance projections use the selected display currency. Existing records keep their own currency; selecting a currency does not convert values.

Transactions store `income`, `expense` or `savings`, amount, currency, category, payment method, note and optional planner occurrence identity. Planner rules are the `rules` database table, not the Settings automation JSON. They support fixed or percentage bases, quantity, once/daily/weekly/monthly cadence, start/end dates, reorder and duplicate actions.

`project` calculates occurrences. Monthly plans clamp their anchor day to a shorter month's last day. Percentage bases are actual income, expenses or non-negative income minus expenses in the occurrence month. A completed occurrence is linked by a unique `ruleId:yyyy-MM-dd` transaction key. Removing the transaction makes that occurrence actionable again. Skip/cancel preferences affect one occurrence, not future repeats.

Safe-to-spend is `max(0, actual net − planned non-income commitments on or after today in the selected period)`. Future planned income is not spendable. For exact calculations and storage types, read [Data reference](DATA_REFERENCE.md).

Detected payment notifications use a conservative local parser. Valid purchases become ordinary editable expense entries after Flutter imports the native queue. A separate confirmation posts only after the database commit. This is not direct bank integration, item recognition or server-side AI summarization.

## Calendar

Calendar is the fixed upper-left shortcut. Its local toolbar switches Year, Month, Week and Day views and shifts the date. Inline agenda add controls retain selected-date entry creation. The Sunday-first calendar differs from the Map's Monday-start week filter.

The year view shows twelve months. Month view uses recorded markers or labels and a draggable collapse handle that reduces to the selected week. Week view has a 24-hour session grid and a finance band; Day view has a visual cover and recorded session/finance agenda. Records are real saved data, not the gaming events in the original reference screenshots. Calendar records retain original currency denominations.

Sessions and entries are indexed by date when their record lists change. The selected date/view are exported as rule context. The day agenda uses the shared adaptive drawer, without a nested draggable sheet. The legacy `dayPanel` preference remains in saved/exported data but no longer controls drawer height. Initial Calendar selection/view currently start at today/month when remounted; exported preferences should not be mistaken for complete view-state restoration.

## Map

Map fills the content area behind fixed glass controls. Pan, pinch and zoom controls change the viewport; Fit centers the selected records or all filtered records. Category chips are a named/icon/color legend: blue Sessions, green Finance, amber Locations and purple Other. Unknown future located actions remain visible in Other.

Timeline modes are day, Monday-start week, month, year and custom inclusive date range. Queries use local calendar boundaries with an exclusive end and do not apply the Logs sheet's 1,000-row cap. Custom selection uses existing wheel pickers. Changing the range clears the selection; view date/period/trace preferences persist.

`MapRecord.parse` accepts direct or nested JSON positions, validates finite latitude/longitude and rejects samples more than two minutes older than the action, or more than one second in its future when a sample timestamp exists. Logs without usable coordinates are not plotted. This is especially important because SQL log triggers retain the position JSON even when its human-readable location is unavailable.

Markers group positions rounded to five decimal places. A dot opens located records with checkboxes and expandable details. No selection traces all category/time-filtered records; a selection limits the chronological trace. Dashed straight lines connect recorded coordinates, not traveled roads or continuous tracking. Opening Map does not request GPS or turn on location logging.

On-demand OpenStreetMap tiles use app identification, visible attribution and a 128 MiB cache configuration. Tile failure leaves saved dots available and displays a connection/retry message. Retry resets the tile layer and evicts failed images without disposing its network provider or changing selected records; a saved-record query failure retries that query separately. No saved coordinates in a timeline is an empty state, not a GPS permission error. Map never requests current GPS location.

Controls use compact 18 px icons/12 px labels with 48 px button touch targets. The action cluster is a two-by-two grid on tall screens and a horizontal strip on short screens, where timeline/log selectors use labeled tooltips. Category chips retain their named/icon/color legend; large grouped dots display `99+` while accessibility labels and their detail drawer retain the full count. Viewport context publishes after 500 ms of inactivity; identical raw query rows skip repeated JSON parsing and marker rebuilds. Current shortcomings and long-history limits are listed in [Application audit](APPLICATION_AUDIT.md).

## Settings and bottom sheets

The shared `panel` implementation lives in `sheets.dart`, a part of `design.dart`, and is the standard bottom drawer for details, forms, selectors, pickers, confirmations and Settings sheets. Default height fits its contents, capped at 70% of the available viewport. Expanded height is 70%; dragging or swiping downward closes the route. Content-fit default and expanded are predefined snap positions, with a closed extent of zero. For long content, default and expanded coincide. The handle toggles default/expanded on tap and exposes increase, decrease and Close sheet accessibility actions. Opening/closing reuse 250/150 ms transitions; reduced motion skips route/handle transitions. Keyboard appearance expands within the remaining viewport.

`PanelContent` provides fixed `header` and `footer` slots around one primary scrollable body. Plain content gets the shared scrolling wrapper; pass `PanelContent(scrollable: true)` for an existing lazy ListView. The legacy `panel(scrollable: true)` wrapper supports plain content without slots. The supplied `PrimaryScrollController` coordinates content scrolling with resizing; do not supply an independent controller or nest a draggable sheet. Short content is measured from its laid-out viewport and scroll extent, without intrinsic layout or constructing a second copy. Long lists remain lazy. Content/metrics changes update the default snap height. Empty/loading content stays scrollable. Picker wheels retain their own wheel interaction while surrounding content uses the drawer controller.

Headers, search/filter controls and primary actions stay outside body scrolling. Save/Cancel remain pinned in forms; contextual Delete actions scroll with the form fields. `PanelActions` places two actions side by side on short/keyboard layouts. `components.dart` owns the reusable `AppButton` (primary, secondary, quiet, saving and destructive-text variants), `PanelActions`, `PanelHeading`, opaque `Surface` cards/containers and liquid-glass `Chrome`. Standard Flutter controls continue to use the shared themes in `Design.theme`; no additional package or parallel styling system is needed.

Settings contains Activity logs, Conditions & automation, saved-transaction posting access, notification sounds, appearance, display currency, category/payment-method management, in-app sound effects, export, restore and clear-data controls.

Activity logs and Conditions & automation share `ActivitySheet`, selected by `initialTab`. Logging, location collection and notification scanning default off. Logs show the newest 1,000 records with expandable action/time/location metadata. Full stored history remains available to Map and export. Central triggers log inserts and the initial clock-out, not every edit/delete or every app interaction.

Conditions support a beginner visual named-location token/radius builder and a structured source editor. Radius units are metres, default 150 m, range 100–1,000 m in 50 m steps. A rule may keep a session running or clock out on leaving. One rule has one configured place; arbitrary map polygons or multiple place arguments are not supported by the current grammar.

The code editor provides contextual completion and line/column parser errors. Validate, Run, Stop and new-rule controls use icons with tooltips. Structured Save leaves a rule paused; Run saves/enables it; Stop disables it without ending the current session. The visual save path enables a condition, subject to the global location toggle and permissions. Up to 100 rules can be saved. Full language examples and limits live in [Rule syntax](../RULE_SYNTAX.md).

Notification sounds select Reminders, Saved transactions or Running sessions, then open the Android channel settings. Android owns the actual sound URI/channel choice. This is separate from the app's `sound` toggle for button/session effects. Running-session notifications default quiet.

Backup exports local data as JSON through native sharing. Restore asks for confirmation, rejects files larger than 20 MiB in the UI and replaces validated data in one database transaction. Native timer/automation state is reset/reconfigured through the Settings workflow. Clear-data requires typed confirmation. These are explicitly user-triggered destructive actions, not automatic startup recovery.

## Architecture and ownership

The architecture has three layers: Flutter presentation, Drift data/calculations and native Android runtime. `screens.dart` groups most screens as `part` files, sharing imports and helper functions. These are not standalone libraries: adding an import directly to a part file is invalid. `design.dart` similarly owns the `flip_clock.dart`, `components.dart` and `sheets.dart` parts.

```mermaid
flowchart LR
  UI[Flutter pages and sheets] --> DB[Drift SQLite]
  DB --> State[Riverpod AppData]
  State --> UI
  State --> Compiler[Rule catalog and compiler]
  Compiler --> Sync[AutomationSync]
  Sync --> Channel[Method channel]
  Channel --> Native[Android services and receivers]
  Native --> Queue[Native durable events]
  Queue --> Sync
  Sync --> DB
  Map[Map viewport] --> Tiles[OSM tiles only]
```

The native queue and pending receipts are transport state, not rule source. Flutter imports native events transactionally, then acknowledges them. System reminders post from native receivers without a Flutter widget. Flutter toasts and settings/expense changes need reconciliation. [Android runtime](ANDROID_RUNTIME.md) specifies the lifecycle and method-channel contract.

## Source map

| File | Owns |
| --- | --- |
| `lib/main.dart` | Bootstrap, router, theme selectors, shell navigation, lifecycle, foreground reconciliation |
| `lib/startup.dart` | Glass preparation deadline, orbit loader, readiness-driven intro |
| `lib/screens.dart` | Shared screen imports/parts, guarded operations, session tiles and quick add |
| `lib/design.dart` | Owning design library, tokens/themes, page layout, motion, navigation and toasts |
| `lib/components.dart` | Reusable buttons, action groups, sheet headings, Surface cards/containers and glass Chrome (design part) |
| `lib/sheets.dart` | Universal content-fit/70% drawer, fixed slots, snapping/dismissal and confirmations (design part) |
| `lib/controls.dart`, `lib/pickers.dart` | Custom choice sheets/selectors and wheel date/time pickers |
| `lib/today.dart`, `lib/flip_clock.dart` | Home, analog clock and elapsed split-flap display |
| `lib/history.dart`, `lib/calendar.dart`, `lib/budget.dart` | Sessions, calendar and Finance pages |
| `lib/map.dart`, `lib/map_records.dart` | Map UI, filters, selection, freshness and range parsing |
| `lib/settings.dart`, `lib/forms.dart` | Settings, list management, backup/reset, session/entry/planner forms |
| `lib/activity.dart`, `lib/rule_editor.dart` | Logs, visual/structured conditions, completion and Run/Stop UI |
| `lib/rule_language.dart` | Catalog, typed snapshots, bounded lexer/parser/compiler |
| `lib/data.dart`, `lib/data.g.dart` | Schema, triggers, reactive data, money/recurrence, generated Drift code |
| `lib/services.dart`, `lib/theme_reveal.dart` | Method-channel wrapper, feedback and theme reveal |
| `lib/automation_sync.dart` | Native config/snapshot transport, event import, deduplication and receipts |
| `android/.../MainActivity.kt` | Method channel, permission intents, SoundPool, resume hook |
| `android/.../SessionService.kt` | Foreground chronometer, HyperIsland, native pending clock-out |
| `android/.../Automation.kt` | Geofences, location job, durable event queue, boot receiver, purchase listener |
| `android/.../RuleProgram.kt` | Native conditions, fresh context, branch deduplication and scoped actions |
| `android/.../RuleNotifications.kt` | Alarm scheduling, recurrence state and reminder posting |
| `android/.../TransactionNotifications.kt` | Post-commit Finance confirmation and destination |
| `android/.../NotificationSoundSettings.kt` | Android channel settings and sound observations |

Native `android/.../` above means `android/app/src/main/kotlin/com/frekihub/freki_hub/`. Dependencies/assets are declared in `pubspec.yaml`; native dependencies in `android/app/build.gradle.kts`.

## Startup, synchronization and performance

`main` renders before glass preparation. SQLite and graphics readiness run concurrently. Graphics has a six-second fallback deadline; initial data streams have a fifteen-second timeout/Retry state and can still recover on late completion. Loader stage text reflects actual readiness, without a fabricated percentage or minimum delay. Retry does not clear records.

`watchAll` caches the four typed tables independently. Preference updates do not reread all session/entry/planner tables. App theme subscribes to theme/sound changes. The shell reconciles after readiness, on resume and approximately every fifteen seconds while foregrounded; `AutomationSync` coalesces overlapping work.

Records and configuration live locally. Native receivers/services exchange data through SharedPreferences and a method channel; this is not cloud synchronization. The UI runs its own animations, but elapsed time and scheduled reminders do not depend on those animations. Device frame times, cold-start latency and OEM background delivery have not been measured in this audit.

## Design contracts

Submitted-action failures use the shared `toast(context, message, error: true)` top pill. It appears below the status-bar safe inset on the root overlay, including above modal drawers. A new message replaces the previous pill; errors remain for eight seconds and other notices for four, with an accessible dismiss button. Long diagnostics wrap and scroll within a bounded height, retaining syntax line/column details. Entrance/exit obey reduced motion; dismissal uses the existing feedback and sound preference. Session, transaction and planner forms, list-name validation, savings goals and syntax validation use this surface instead of inline error text or an error dialog. Failed category/payment-method writes retain the entered name and last saved list. Persistent startup Retry and Map availability states remain visible because they describe ongoing page availability.

Keep bundled Geist/Geist Mono, Lucide icons, neutral light/dark surfaces, opaque data cards and liquid glass for fixed chrome. `Surface`, `Chrome`, `PageBody`, `panel`, `toast`, `selectField` and wheel pickers are shared contracts. Standard page headers reserve 80 px for fixed top shortcuts; Today's compact header starts at 16 px with horizontal shortcut clearance. Content leaves bottom navigation clearance and uses bounded readable width.

Motion uses `Motion.duration` and shared curves. Preserve reduced motion, tooltips/semantics, enlarged text, keyboard/inset behavior, minimum touch controls and sound preference. `withFeedback`/`ActionFeedback` provide throttled interaction effects; elapsed ticks do not play sounds. OS permission/share/file/channel dialogs remain OS-owned.

## Extending a feature

1. Choose the existing page/form/data owner; inspect its relevant source and tests.
2. Reuse shared design controls rather than replacing them with default platform dropdowns.
3. Preserve money/date and native event reconciliation invariants.
4. Register meaningful observable fields/types/completion in `RuleCatalog` and snapshots or native context. New preference keys are automatically readable under `settings.*` as strings unless explicitly typed.
5. Register a new target when introducing a new resource. Add modifying actions to compiler and native runtime under the correct target; do not permit arbitrary actions.
6. Keep source, compiled program, live snapshot and outboxes separate. Preserve branch-change deduplication and Run/Stop semantics.
7. Update syntax and affected documentation, run meaningful checks, then commit/push within the user's authorized workflow.

Consult [Development](DEVELOPMENT.md) for targeted checks and [Application audit](APPLICATION_AUDIT.md) before changing a known risky area.
