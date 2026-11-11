# CLAUDE.md — window-manager

App switching on ⌥+digits and window placement on ⌥+keys. See the repo root `CLAUDE.md` for shared
conventions.

- Keys: ⌥1–8 apps, ⌥9 / ⌥0 left / right, ⌥- maximize toggle,
  ⌥M minimize. Settings: `APPS` / `APP_KEYS`, `WINDOW_KEYS`, `MOD`.
- When combined with windows-compat (`HSVariants.has("windows-compat")`), `MOD` is replaced by
  `COMBINED_MOD` (⌃⌥) because windows-compat owns ⌥ (including ⌥1–9).
- Design rule: **pressing the same key again advances** (next window, next snap width, un-maximize).
  New features should follow it.
- State lives in the global `WindowManager` table (aliased `M`), initialized with `M.x = M.x or ...`.
  `M.beforeMaximize` holds the pre-maximize frame per window ID.
- App focus finds windows on other Spaces through a window cache
  (`forceRefreshOnSpaceChange` + a `keepActive()` warmer filter + per-app filters).
- `hs.window.animationDuration = 0` is intentional.
