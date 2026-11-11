-- =====================================================================
-- ウィンドウマネージャ (Hammerspoon)
-- =====================================================================
-- ⌥+数字でアプリを切り替え、⌥+キーでフォーカス中のウィンドウの位置と大きさを変える。
-- 「同じキーをもう一度押すと次へ進む」動きで統一している。
--
-- キー:
--   ⌥+1〜8   アプリを起動 / 前面化。前面なら同じアプリの次のウィンドウへ
--            1 VS Code / 2 PyCharm / 3 cmux / 4 Sourcetree / 5 Slack / 6 Chrome / 7 Claude / 8 メモ
--   ⌥+9      左に配置。続けて押すと幅が 1/2 → 2/3 → 1/3
--   ⌥+0      右に配置。続けて押すと幅が 1/2 → 2/3 → 1/3
--   ⌥+=      最大化
--   ⌥+-      元の大きさに戻す（⌥+9 / 0 / = / g で動かす前の位置と大きさ）
--   ⌥+g      グリッドを表示し、マス目を選んで手で配置する
--   ⌥+m      最小化（Dock にしまう）。しまった直後にもう一度押すと元に戻す
--
-- windows-compat と組み合わせて導入した場合、windows-compat が ⌥ を Win キーとして使うため、
-- 修飾キーを ⌥ → ⌃⌥ に置き換える（COMBINED_MOD で変更できる）。
--
-- 設定変更後は Hammerspoon コンソールで hs.reload() を実行する。
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- 修飾キー
local MOD = { "alt" }

-- windows-compat と組み合わせて導入した場合の修飾キー
local COMBINED_WITH = "windows-compat"
local COMBINED_MOD  = { "ctrl", "alt" }

-- アプリ定義。bundleIDs を上から順に試し、見つからなければ name（アプリ名）で探す。
-- bundle ID の調べ方: osascript -e 'id of app "Slack"'
local APPS = {
  vscode     = { name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  pycharm    = { name = "PyCharm",            bundleIDs = { "com.jetbrains.pycharm",         -- Professional
                                                            "com.jetbrains.pycharm.ce" } },  -- Community
  cmux       = { name = "cmux",               bundleIDs = { "com.cmuxterm.app" } },
  sourcetree = { name = "Sourcetree",         bundleIDs = { "com.torusknot.SourceTreeNotMAS" } },
  slack      = { name = "Slack",              bundleIDs = { "com.tinyspeck.slackmacgap" } },
  chrome     = { name = "Google Chrome",      bundleIDs = { "com.google.Chrome" } },
  claude     = { name = "Claude",             bundleIDs = { "com.anthropic.claudefordesktop" } },
  notes      = { name = "Notes",              bundleIDs = { "com.apple.Notes" } },
}

-- ⌥+キー → アプリ
local APP_KEYS = {
  ["1"] = "vscode",
  ["2"] = "pycharm",
  ["3"] = "cmux",
  ["4"] = "sourcetree",
  ["5"] = "slack",
  ["6"] = "chrome",
  ["7"] = "claude",
  ["8"] = "notes",
}

-- ⌥+キー → ウィンドウ操作
local WINDOW_KEYS = {
  left     = "9",
  right    = "0",
  maximize = "=",
  restore  = "-",
  grid     = "g",
  minimize = "m",
}

-- ⌥+g のグリッドのマス目（横x縦）
local GRID_SIZE = "6x4"

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

-- ルートの install.sh で導入した場合、loader.lua が HSVariants を用意する。
-- この init.lua だけを使う場合は HSVariants がないため、上の修飾キーのまま動く。
if HSVariants and HSVariants.has(COMBINED_WITH) then
  MOD = COMBINED_MOD
end

-- ローカル変数からのみ参照されるオブジェクトは GC で回収され、
-- ホットキーやウォッチャーが停止する。グローバルな表に保持して回収を防ぐ。
WindowManager = WindowManager or {}
local M = WindowManager

M.original = M.original or {}  -- ウィンドウID → 本設定で動かす前の位置と大きさ
M.placed   = M.placed or {}    -- ウィンドウID → 本設定が最後に置いた位置と大きさ

hs.window.animationDuration = 0

local function log(fmt, ...)
  print(string.format("[wm] " .. fmt, ...))
end

-- ---------------------------------------------------------------------
-- アプリの解決 / 起動
-- ---------------------------------------------------------------------

-- 起動中のアプリを取得する（bundle ID 優先、無ければアプリ名）。未起動なら nil。
local function runningApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    local app = hs.application.get(id)
    if app then return app end
  end
  return hs.application.get(spec.name)
end

-- アプリを起動する（bundle ID を順に試し、最後にアプリ名でフォールバック）。
local function launchApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    if hs.application.launchOrFocusByBundleID(id) then return true end
  end
  if hs.application.launchOrFocus(spec.name) then return true end
  log("起動できない: %s（このMacに未インストール？）", spec.name)
  return false
end

-- ---------------------------------------------------------------------
-- ウィンドウ列挙（別デスクトップ対応）
-- ---------------------------------------------------------------------
-- macOS は今いるデスクトップのウィンドウしか列挙できない。hs.window.filter は一度認識した
-- ウィンドウをキャッシュし続けるので、別デスクトップのウィンドウも返せる。これを一次ソースにする。
hs.window.filter.forceRefreshOnSpaceChange = true

local WINDOW_FILTER = { allowRoles = "AXStandardWindow" }

-- 保温役: 空フィルタを常時アクティブにして、ウィンドウの追跡を止めない。
M.windowWarmer = hs.window.filter.new(false, "wm.warm")
M.windowWarmer:keepActive()

M.appFilters = M.appFilters or {}

local function filterForApp(app)
  local name = app:name()
  if not name then return nil end
  if not M.appFilters[name] then
    local wf = hs.window.filter.new(false, "wm.wf." .. name)
    wf:setAppFilter(name, WINDOW_FILTER)
    wf:keepActive()
    M.appFilters[name] = wf
  end
  return M.appFilters[name]
end

-- 対象アプリの通常ウィンドウを、ウィンドウID順（押すたびに変わらない並び）で返す。
local function standardWindows(app)
  local seen, wins = {}, {}
  local function add(w)
    local id = w and w:id()
    if id and not seen[id] then
      seen[id] = true
      wins[#wins + 1] = w
    end
  end

  local wf = filterForApp(app)
  if wf then
    for _, w in ipairs(wf:getWindows()) do add(w) end   -- 別デスクトップ含む
  end
  for _, w in ipairs(app:allWindows()) do               -- 現デスクトップ分の補完
    if w:isStandard() then add(w) end
  end

  table.sort(wins, function(a, b) return a:id() < b:id() end)
  return wins
end

-- ---------------------------------------------------------------------
-- フォーカス / 巡回（⌥+数字）
-- ---------------------------------------------------------------------

-- 「ウインドウ」メニューの名前。アプリや言語設定で表記が違うので、上から順に探す。
local WINDOW_MENU_NAMES = { "ウインドウ", "ウィンドウ", "Window" }

-- アプリの「ウインドウ」メニューにあるウィンドウ一覧から、win をタイトルで選ぶ。選べたら true。
-- 手でこのメニューから選んだときと同じく、別デスクトップのウィンドウならそこへ移動する。
-- 同じタイトルが複数あると上にある方が選ばれる。
local function selectFromWindowMenu(app, win)
  local title = win:title()
  if not title or title == "" then return false end
  for _, menu in ipairs(WINDOW_MENU_NAMES) do
    if app:selectMenuItem({ menu, title }) then return true end
  end
  return false
end

-- ウィンドウをフォーカスする。別デスクトップへの移動は macOS 自身にさせる。
--   別アプリから切り替えるとき → win:focus() だけ。アプリの切り替えで macOS が移動する
--                                 （システム設定の「アプリケーションの切り替えで…スペースに移動」）。
--   同じアプリの中で巡回するとき → アプリの切り替えにならないので macOS は移動しない。
--                                   代わりに「ウインドウ」メニューから選んで移動させる。
-- hs.spaces.gotoSpace は Mission Control を開いてボタンを押す仕組みで、Mission Control が
-- 開いたまま止まることがあるため使わない。
local function focusWindow(win)
  if win:isMinimized() then win:unminimize() end

  local spaces = hs.spaces.windowSpaces(win) or {}
  local screen = win:screen()
  local activeSpace = screen and hs.spaces.activeSpaceOnScreen(screen)

  local onActiveSpace = false
  for _, s in ipairs(spaces) do
    if s == activeSpace then onActiveSpace = true break end
  end

  -- 別デスクトップにある、前面アプリ自身のウィンドウ → ウインドウメニューから選ぶ
  if not onActiveSpace and spaces[1] and activeSpace then
    local app = win:application()
    local front = hs.application.frontmostApplication()
    if app and front and front:pid() == app:pid() and selectFromWindowMenu(app, win) then
      return
    end
  end
  win:focus()
end

-- wins の中で、今フォーカスしているウィンドウの次へ移動する（末尾の次は先頭）。
local function focusNextIn(wins)
  if #wins == 0 then return false end
  local current = hs.window.focusedWindow()
  local idx = 0
  if current then
    for i, w in ipairs(wins) do
      if w:id() == current:id() then idx = i break end
    end
  end
  local nextIdx = idx % #wins + 1
  focusWindow(wins[nextIdx])
  return true
end

-- アプリキーの挙動:
--   未起動           → 起動する
--   起動中・非最前面 → そのアプリへフォーカス（直前に使っていたウィンドウ）
--   起動中・最前面   → 同じアプリの次のウィンドウへ巡回
local function focusApp(spec)
  local app = runningApp(spec)
  if not app then
    launchApp(spec)
    return
  end

  local front = hs.application.frontmostApplication()
  if front and front:pid() == app:pid() then
    if focusNextIn(standardWindows(app)) then return end
  else
    local win = app:mainWindow() or standardWindows(app)[1]
    if win then
      focusWindow(win)
      return
    end
  end

  launchApp(spec)  -- ウィンドウが1枚も無い → 起動しなおして開かせる
end

-- ---------------------------------------------------------------------
-- ウィンドウ配置（⌥+9 / 0 / = / - / g / m）
-- ---------------------------------------------------------------------

-- 「元の大きさ」に戻せるよう、本設定で動かす前の位置と大きさをウィンドウごとに覚えておく。
-- 続けて配置を変えても最初の位置を保つ。ただし本設定で動かした後に手で動かしていれば、
-- その位置を新しい「元の大きさ」とする。
local function copyFrame(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- 配置に使う領域（メニューバーと Dock を除いた範囲）
local function workArea(screen)
  return screen:frame()
end

-- ターミナル等は文字単位でしかリサイズできないので、多少のずれは同じ位置とみなす
local TOLERANCE = 20

local function near(f, t)
  return math.abs(f.x - t.x) <= TOLERANCE and math.abs(f.y - t.y) <= TOLERANCE
    and math.abs(f.w - t.w) <= TOLERANCE and math.abs(f.h - t.h) <= TOLERANCE
end

-- 配置を変える直前に呼ぶ。元の位置と大きさを覚える
local function remember(w)
  local id, f = w:id(), w:frame()
  local placed = M.placed[id]
  if not M.original[id] or not (placed and near(f, placed)) then
    M.original[id] = copyFrame(f)
  end
end

-- 配置を変えた直後に呼ぶ。本設定が置いた位置を覚える（手で動かしたかの判定に使う）
local function placedBy(w)
  M.placed[w:id()] = copyFrame(w:frame())
end

local function place(w, frame)
  remember(w)
  w:setFrame(frame, 0)
  placedBy(w)
end

local SNAP_RATIOS = { 1 / 2, 2 / 3, 1 / 3 }

local function snapFrame(a, side, r)
  if side == "left" then return { x = a.x, y = a.y, w = a.w * r, h = a.h } end
  return { x = a.x + a.w * (1 - r), y = a.y, w = a.w * r, h = a.h }  -- right
end

-- 同じ向きで続けて押すと 1/2 → 2/3 → 1/3 と幅が変わる
local function snap(side)
  local w = hs.window.focusedWindow()
  if not w then return end
  local a = workArea(w:screen())
  local cur = w:frame()
  local nextIdx = 1
  for i, r in ipairs(SNAP_RATIOS) do
    if near(cur, snapFrame(a, side, r)) then nextIdx = i % #SNAP_RATIOS + 1 break end
  end
  place(w, snapFrame(a, side, SNAP_RATIOS[nextIdx]))
end

local function maximize()
  local w = hs.window.focusedWindow()
  if w then place(w, workArea(w:screen())) end
end

-- 本設定で動かす前の位置と大きさに戻す
local function restore()
  local w = hs.window.focusedWindow()
  if not w then return end
  local id = w:id()
  local original = M.original[id]
  if not original or near(w:frame(), original) then
    -- 何も起きないと効いていないように見えるので、戻す位置がないことを知らせる
    hs.alert.show("No undo history", 1)
    M.original[id] = nil
    return
  end
  w:setFrame(original, 0)
  M.original[id] = nil
  M.placed[id] = nil
end

-- グリッドを表示し、フォーカス中のウィンドウを手で配置する。
-- マス目の文字キーを2つ押すと、その2マスを対角とする範囲に配置される。Esc で閉じる。
-- hs.grid は表示中の Tab / ⇧Tab で配置するウィンドウを切り替えるが、切り替えた先は ⌥- で
-- 戻せないため使わせない。同じキーの hs.hotkey は後から有効にしたものが優先されるので、
-- グリッドを表示した後に何もしない Tab / ⇧Tab を割り当て、閉じたら消す。
local function unblockGridKeys()
  for _, hk in ipairs(M.gridBlock or {}) do hk:delete() end
  M.gridBlock = nil
end

local function showGrid()
  local w = hs.window.focusedWindow()
  if not w then return end
  remember(w)
  unblockGridKeys()
  hs.grid.show(function()
    unblockGridKeys()
    if hs.window.get(w:id()) then placedBy(w) end
  end)
  local noop = function() end
  M.gridBlock = {
    hs.hotkey.bind({}, "tab", noop),
    hs.hotkey.bind({ "shift" }, "tab", noop),
  }
end

local function focusedId()
  local w = hs.window.focusedWindow()
  return w and w:id() or false
end

-- 最小化。しまった直後にもう一度押すと、しまったウィンドウを元に戻す。
-- しまうと macOS が別のウィンドウへフォーカスを移すので、そのフォーカス先を覚えておき、
-- フォーカスがそこから動いていなければ「直後」とみなす。別のウィンドウを選んでから押すと、
-- そのウィンドウをしまう。
local FOCUS_SETTLE = 0.5

local function toggleMinimize()
  local last = M.minimizedWin
  if last and last:isMinimized()
    and (M.focusAfterMinimize == nil or M.focusAfterMinimize == focusedId()) then
    last:unminimize()
    last:focus()
    M.minimizedWin = nil
    return
  end

  local w = hs.window.focusedWindow()
  if not w then return end
  w:minimize()
  M.minimizedWin = w
  M.focusAfterMinimize = nil  -- フォーカスが移り終わるまでは「直後」とみなす
  if M.minimizeTimer then M.minimizeTimer:stop() end
  M.minimizeTimer = hs.timer.doAfter(FOCUS_SETTLE, function()
    M.focusAfterMinimize = focusedId()
  end)
end

-- ---------------------------------------------------------------------
-- ホットキー
-- ---------------------------------------------------------------------

if M.hotkeys then
  for _, hk in ipairs(M.hotkeys) do hk:delete() end
end
M.hotkeys = {}

local function bind(mods, key, fn)
  M.hotkeys[#M.hotkeys + 1] = hs.hotkey.bind(mods, key, fn)
end

for key, appKey in pairs(APP_KEYS) do
  bind(MOD, key, function() focusApp(APPS[appKey]) end)
end

bind(MOD, WINDOW_KEYS.left,     function() snap("left") end)
bind(MOD, WINDOW_KEYS.right,    function() snap("right") end)
bind(MOD, WINDOW_KEYS.maximize, maximize)
bind(MOD, WINDOW_KEYS.restore,  restore)
bind(MOD, WINDOW_KEYS.grid,     showGrid)
bind(MOD, WINDOW_KEYS.minimize, toggleMinimize)

hs.grid.setGrid(GRID_SIZE)
hs.grid.setMargins("0x0")

hs.alert.show("ウィンドウマネージャ 読み込み完了", 0.8)
