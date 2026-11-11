# CLAUDE.md

A collection of standalone Hammerspoon configs ("variants"), each aimed at a different kind of user.
The audience is general Hammerspoon users who install a variant and customize it.

## Layout

`README.md` at the root is a short user-facing overview; update it when a variant is added or removed.

```
install.sh         Pick one or more variants; writes ~/.hammerspoon/init.lua that calls loader.lua
loader.lua         Loads the picked variants (pcall each), tracks keys, warns on key conflicts
tests/
  install-test.sh  Checks install.sh end to end against a throwaway $HOME
.github/workflows/
  test.yml         CI: install-test.sh + sh -n on macOS, luac5.4 -p on Ubuntu
variants/
  windows-compat/  Windows key bindings on macOS (Ctrl→⌘, Win→⌥ snap/shortcuts, Alt+Tab, Finder, screenshots)
  window-manager/  App switching (⌥1–8) + window placement (⌥9/0/=/-/G/M)
```

Each variant directory contains exactly:

| File | Purpose |
|------|---------|
| `init.lua` | The whole config, self-contained (no shared modules) |
| `README.md` | User-facing docs (Japanese) |
| `CLAUDE.md` | Notes for Claude about that variant |

The SMC-PAD MIDI config lives in the separate `hammerspoon-smcpad` repo.

## Conventions (all variants)

- **Self-contained**: a variant must still work alone as `~/.hammerspoon/init.lua` (copied as-is).
  Do not share code between variants; duplicate small helpers instead. Guard every use of the
  loader API with `if HSVariants then ...`.
- **Combinable**: variants are installed only through the root `install.sh`, which auto-discovers
  `variants/*/init.lua` (list text = first `# ` heading of its README) and generates a marked
  `~/.hammerspoon/init.lua` (backup: `init.lua.before-variants`, never overwritten). `loader.lua`
  sets `HSVariants` before loading anything:
  - `HSVariants.has(name)`: whether `name` is also selected (order-independent). Use it to shift a
    variant's keys when combined (see window-manager `COMBINED_MOD`).
  - `HSVariants.claim(mods, key)`: register keys handled outside `hs.hotkey` (eventtaps). Keys bound
    with `hs.hotkey.new/bind` during load are recorded automatically; duplicates across variants are
    shown as an alert and `[variants] キーの重複:` console lines.
  - Variants must not modify other variants' tables or `HSVariants`.
- Current combination rule: windows-compat owns ⌥ (Win key), ⌃ (Ctrl→⌘), ⌘Tab/⌘F4. window-manager moves to
  ⌃⌥ when combined with it. Check that the combined set has no conflicts when keys change.
- `init.lua` structure: header comment listing features/keys → user settings between `▼▼▼` and
  `▲▲▲` → implementation.
- Long-lived objects (eventtaps, watchers, timers, hotkeys) are stored in one global namespace
  table per variant (`WinCompat`, `WindowManager`) so they survive GC and can be cleaned
  up / reused across `hs.reload()`.
- Apps are resolved by `bundleIDs` (in order) with `name` as fallback; missing apps must not error.
- The variant must not change macOS system settings; quitting Hammerspoon undoes everything.
- If a variant changes a Hammerspoon-wide value (e.g. `hs.window.animationDuration`), say so in its README.
- Key bindings assume the US keyboard layout; note layout-dependent keys in the variant README.
- Language: comments, READMEs, and commit messages in **Japanese** (READMEs use the plain
  `である` style). Identifiers in English.
- When keys or settings change, update the header comment in `init.lua` and the `README.md` together.

## Writing for users (comments, READMEs, install.sh messages)

Everything in the repo except `CLAUDE.md` files is read by general users. Write it for them:

- Describe what the config does, how to use and customize it, and the limits a user may hit
  (macOS permissions, conflicting shortcuts) with what to do about them.
- Do **not** mention alternatives that were considered and dropped (e.g. "Karabiner is not
  needed", "does not imitate i3/yabai"), the maintainer's own setup, the talk/study group, other
  repos the code was copied from, or design-discussion history.
- Do **not** leave maintainer to-dos such as "verify on real hardware" / "実機で要確認" / placeholders
  to check. Track unverified behavior in the PR description instead.
- Code comments explain *why* the code is written that way (macOS / Hammerspoon constraints),
  not how it came about.

## Load / test

Variant behavior is verified on a real Mac. `install.sh` has an automated test:
`./tests/install-test.sh` (it points `HOME` at a temp dir, so the real `~/.hammerspoon` is never
touched). Run it whenever `install.sh` changes.

- `install.sh` runs under `#!/bin/sh`, which is bash 3.2 on macOS. Its variable-name parser is not
  multibyte-aware, so `"$VAR（..."` swallows the first byte of `（` into the name and `set -u` then
  aborts. Wherever a full-width character follows an expansion, brace it: `"${VAR}（..."`. Test and
  review under `sh`, not `zsh` — zsh does not reproduce it.
- Install: `./install.sh <name> [<name>...]` (no args = numbered menu); uninstall: `./install.sh --uninstall`.
- Reload: `hs.reload()` in the Hammerspoon console (install.sh does this via `hs` CLI if available).
- Accessibility permission is required for all variants.
- Syntax check (if Lua is installed): `luac -p loader.lua variants/*/init.lua`; `sh -n install.sh`.
- CI (`.github/workflows/test.yml`) runs the install test and both syntax checks on every PR and
  push to main. When adding a test, add it to the workflow too.

If you change behavior you cannot verify on a Mac, list what needs checking in the PR description
(not in READMEs or comments).
