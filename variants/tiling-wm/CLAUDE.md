# CLAUDE.md — tiling-wm

Keyboard-driven tiling and app focus. Its own key scheme, not a reproduction of another WM. See the
repo root `CLAUDE.md` for shared conventions.

- When combined with windows-compat (`HSVariants.has("windows-compat")`), `MOD`/`MOD_SHIFT`/`SNAP_MOD`
  are replaced by `COMBINED_*` (⌃⌥ / ⌃⌥⇧ / ⌃⌥⌘) because windows-compat owns ⌥.
- Two modifier layers: `MOD` (⌥) for windows/apps, `SNAP_MOD` (⌃⌥) for snapping. Keep new
  bindings in the right layer.
- Design rule: **pressing the same key again advances** (next window, next layout, next snap
  width). New features should follow it.
- State lives in the global `TilingWM` table (aliased `M`) and is initialized with `M.x = M.x or ...`
  so layout, ratio, order and floating windows survive `hs.reload()`.
- Layouts: `tall` (main + stack), `columns`, `monocle`. `M.order` holds window IDs; the first is main.
- App focus reuses the cross-Space window cache approach from hammerspoon-smcpad
  (`forceRefreshOnSpaceChange` + a `keepActive()` warmer filter + per-app filters).
- Tiling targets windows on the current Space and focused screen only; `EXCLUDE_APPS` and floating
  windows are skipped. Auto-tile is debounced with `hs.timer.delayed`.
- `hs.window.animationDuration = 0` is intentional.
- Settings: `APPS` / `APP_KEYS`, `GROUPS` (first app is main), `GAP`, `MAIN_RATIO`, `EXCLUDE_APPS`.
- Layout save/restore (⌃⌥S / ⌃⌥L) stores one layout in `hs.settings` (`TilingWM.savedLayout`), keyed by
  bundle ID + window title, falling back to the app's remaining windows in saved order.
