# CLAUDE.md — windows-compat

Reproduces Windows key bindings on macOS for temporary Mac users. See the repo root `CLAUDE.md`
for shared conventions.

- Keys map by **physical position**, not label: Mac ⌃ = Windows Ctrl, ⌥ = Win, ⌘ = Alt.
- State lives in the global `WinCompat` table (key eventtap, tap watchdog, app watcher, window
  switcher, menubar item).
- One `hs.eventtap` rewrites ⌃ shortcuts (`CTRL_TO_CMD`) to ⌘, plus Home/End, ⌃←/→, ⌃Backspace.
  The frontmost app's bundle ID is cached via an app watcher; apps in `EXCLUDE_APPS` (terminals,
  where ⌃C must interrupt) are never rewritten.
- ⌘Tab uses `hs.window.switcher` (per-window), ⌘F4 closes the window, or quits
  the app on its last standard window (Finder is never quit).
- Every keyDown gets a decision (pass / consume / rewrite) stored in `WinCompat.decisions`, and the
  matching keyUp reuses it. Win-key (⌥) shortcuts are handled inside the eventtap
  (not `hs.hotkey`) so that keys rewritten to ⌥ (⌃←/→, ⌃Backspace) never trigger them; their actions
  run via `hs.timer.doAfter(0)` to keep the tap callback fast. ⌥ shortcuts ignore `EXCLUDE_APPS`.
- F5 → ⌘R respects `EXCLUDE_APPS`.
- ⌥1〜⌥9 come from `TASKBAR_APPS` (bundleIDs with name fallback; cycles windows by id when frontmost).
- Clipboard history (⌥V) is stored in `hs.settings` under `WinCompat.clipHistory`; concealed/transient
  pasteboard types are skipped.
- The cheat sheet (⌥/) is an `hs.alert`; first-load display is recorded in `hs.settings`.
- On/off toggle: menubar "Win"/"Mac" item or ⌃⌥⌘W. Disabled mode must pass every key through.
- ⌃←/→ collides with the macOS Space-switching shortcut; the README tells users how to turn that off.
- Keys handled inside the eventtap are registered with `HSVariants.claim` (when loaded via loader.lua)
  so conflicts with other variants are detected. Update the claim block when eventtap keys change.
