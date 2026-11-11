# CLAUDE.md — window-manager

App switching on ⌥+digits and window placement on ⌥+keys. See the repo root `CLAUDE.md` for shared
conventions.

- Keys: ⌥1–8 apps, ⌥9 / ⌥0 left / right, ⌥= maximize, ⌥- restore, ⌥G grid,
  ⌥M minimize (pressing again right after restores it). Settings: `APPS` / `APP_KEYS`, `WINDOW_KEYS`, `GRID_SIZE`, `MOD`.
- When combined with windows-compat (`HSVariants.has("windows-compat")`), `MOD` is replaced by
  `COMBINED_MOD` (⌃⌥) because windows-compat owns ⌥ (including ⌥1–9).
- Design rule: **pressing the same key again advances** (next window, next snap width).
  New features should follow it.
- State lives in the global `WindowManager` table (aliased `M`), initialized with `M.x = M.x or ...`.
  `M.original` holds the frame before this config first moved a window (⌥- restores it); `M.placed`
  holds the frame this config last set, so a manual move in between resets `M.original`.
- App focus finds windows on other Spaces through a window cache
  (`forceRefreshOnSpaceChange` + a `keepActive()` warmer filter + per-app filters).
- `hs.window.animationDuration = 0` is intentional.
