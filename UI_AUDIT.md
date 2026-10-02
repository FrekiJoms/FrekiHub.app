# UI audit and applied changes

## October 2, 2026 re-audit

Reviewed all five main pages, record forms, settings sheets, shared navigation, feedback, calendar lookup, budget projections and Android notification integration.

- Navigation: removed the invisible center overlay that swallowed nearby Calendar/Sessions taps. Center hold-and-drag quick-add and accessible quick-add actions remain available; the existing elastic selection animation stays isolated to its controller.
- Sessions: placed the visible condition link in the card content instead of the constrained trailing area. Duration retains its own alignment. External filter resets now update dropdown state.
- Calendar: index sessions and transactions once when record lists change, rather than scanning all records for every calendar cell. Persist sheet height after 250 ms of inactivity and on close, rather than every drag frame. Constrain the month heading between its navigation controls on narrow displays.
- Budget: use equal-width summary columns with bounded amounts; remove redundant nested scaling and duplicate completed-plan timeline rows. Cache monthly projection totals and recorded occurrence IDs within each calculation.
- Forms/storage: guard date/time picker callbacks and transaction errors after disposal; prevent repeated file-picker launches and report picker failures. Remove unused session form and native timer parameters.
- Today: refresh daily totals at midnight and handle connectivity plugin failures without interrupting the page. Timer controls and automation switches now use the shared sound/haptic feedback; bulk-selection checkboxes do too.
- Motion: retain slide/fade page switching, split-flap digits and elastic navigation. Limit staggered card entrances to the first five content sections, with system reduced-motion respected.
- Shared cards: add a clipped transparent Material layer so tap ripples remain visible above the surface decoration across Settings and Budget.
- Notifications: make saved-transaction permission available directly from Settings and retry pending durable receipts when enabled. Existing ongoing-session notifications and purchase receipts cover the useful immediate actions. Periodic location samples remain silent. Receipt posting continues after database commit and retries denied delivery without duplicating transactions.

Limitations: purchases queued while Flutter is closed are reconciled when the app opens/resumes. Condition links still use the automatic-session note's location name; editing that note removes the link. Background reminders and immediate closed-app database imports require separate scheduling work. No APK rebuild or device installation in this audit; Android visual appearance and animation frame timings need device verification.

Validation: all 13 Flutter tests passed, including all five main pages at 320 × 720 with 1.3× text in the dark theme, dropdown resets, center-adjacent tab taps, hold-drag quick-add, startup timeout recovery, automation reconciliation, and purchase receipt retry/rollback behavior. These are widget/database checks, not on-device performance measurements.

Reviewed Today, Calendar, Sessions, Budget, Settings, session/transaction/rule forms, quick-add, shared dialogs, sheets, navigation and feedback from the Flutter source.

- Shared layout: bounded 720 px reading width, adaptive 16/24 px gutters, consistent section gaps and headers that reserve space for fixed settings without narrowing page titles.
- Typography and surfaces: restrained Geist hierarchy, explicit neutral light/dark container and secondary-text colors, 24 px cards and softer elevation.
- Controls: 16 px field corners, visible focus/error borders, consistent button spacing and 48 px icon controls. Floating navigation retains liquid glass; scrolling information uses opaque surfaces.
- Today: clearer page identity, calmer offline notice, bounded numerical values and session-note previews.
- Sessions: phone-friendly list by default, optional table retaining column controls and bulk selection; paired filters fit narrow screens.
- Budget: consistent month selector, savings heading and numerical values that scale down within available width.
- Calendar: system bottom inset clearance, compact week fallback on short displays and record labels only when cells have enough height.
- Settings: clearer storage heading and currency explanation consistent with calendar behavior.
- Forms: consistent sheet gutters, keyboard-aware sheets with bounded width/height, and shared focused/error input styling.
- Motion: shorter tab exit with shared easing; existing reduced-motion handling and haptic/sound feedback retained.

Validation: Flutter static analysis and whitespace checks. No APK rebuild, device screenshot comparison or runtime layout inspection in this pass; phone appearance and enlarged-text layouts still need device verification.

## Compactness and scrolling follow-up

Reduced the Today clock from 218 to 164 px, recent preview from six to three sessions, shared card padding to 20 px, page gaps to 12 px and large section gaps to 16 px. Budget charts use a 150 px footprint. Session tables have a bounded vertical list and a separate horizontal scroll surface, with pinch/pan removed. PageStorage keys retain page scroll offsets. Tab and settings changes use direction-aware slide/fade transitions; outgoing pages ignore touches and pause tickers, and system reduced-motion disables the transition duration. Static analysis passed; device behavior remains unverified.

## Sessions page audit

Collapsed the four filters by default with an animated reveal and active-filter count. Added sorting and direction controls for both list and table, plus a clear-filters/search action. The phone list uses lazy rows inside a bounded scrolling viewport with a scrollbar. Table instructions only appear for table mode. Empty results disable selection; stale deleted IDs and unavailable month filters are cleared when data updates. Equal sort values use timestamp/ID tie-breaks. The date/time formatting sheet scrolls and its time-format choices provide feedback. Session detail remains accessible through existing record transitions and edit forms. Static analysis passed; device visuals, gestures and enlarged-text verification remain pending.
