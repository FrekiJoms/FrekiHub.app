# UI audit and applied changes

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
