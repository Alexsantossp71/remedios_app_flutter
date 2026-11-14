# The Flutter app adopts the React PWA's visual identity (V5 design system)

**Date**: 2026-11-14

## Context

The project ships two products with the same promise: the native Flutter
app (Android/web) and the React PWA "Remédios na Hora"
(alexsantossp71-lgtm/remedios_app). The PWA already carries a mature,
hand-rolled design system — teal brand palette (`#0f766e`/`#0d9488`),
Inter typography, radial glow backdrop, gradient dashboard hero with
decorative rings, glass surfaces and soft-shadow cards — while the Flutter
app ran its own "V3 Clínico calmo" theme (blue seed, Nunito).

A user alternating between the two products sees two different brands for
the same service. Monetization plans (AdMob, Play listing) make brand
recognition more valuable: the store listing, screenshots and the app
itself must look like the product the user may already know from the web.

## Decision

1. The Flutter app adopts the PWA's visual identity as **theme V5**:
   the exact hex tokens from the PWA's `tailwind.config.js` and
   `src/index.css` live in `lib/core/design/brand_colors.dart` — one
   source of truth, translated by hand from the CSS literals.
2. The signature components become reusable widgets in
   `lib/core/design/`: `AppShell` (radial glow), `DashboardHero`
   (gradient + rings + shadow), `StatCard`, `QuickAction`, `RecordCard`
   and `BrandMark`. Screens consume them instead of re-decorating
   Containers.
3. **Inter** ships bundled in the APK (`assets/fonts/Inter-*.ttf`,
   static weights 400/600/700/800) — no runtime fetch, works offline.
   Nunito stays registered for the legacy V3 theme only.
4. `AppTheme.light()/dark()` now return V5; `ThemeMode.system` is
   unchanged (the PWA also follows the system via `darkMode: 'media'`).
   V3 remains compilable as documented legacy, not wired anywhere.
5. Adoption is incremental: this decision ships the tokens, the widgets
   and the Home (Today) screen as proof of concept. Remaining screens
   migrate in follow-up PRs — no big-bang rewrite.

## Consequences

- Both products share one visual identity; screenshots and store
  assets can be produced against either surface.
- Hover states from CSS (`.quick-action`, `.record-card`) map to
  `MouseRegion` + `AnimatedContainer`; on touch, InkWell ripples replace
  hover. Dashed borders (empty states) intentionally wait — no new
  dependency until an empty state actually needs it.
- The React PWA remains the reference implementation: when its design
  changes, the tokens here are updated to match, and vice versa.
