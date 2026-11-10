-- =====================================================================
-- Windows互換モード (Hammerspoon)
-- =====================================================================
-- Windows のキー操作を macOS 上で再現する。
-- キーの対応は刻印ではなく物理位置に基づく（Windows: Ctrl|Win|Alt、Mac: ⌃|⌥|⌘）。
--   ⌃ (Windows の Ctrl の位置) → Ctrl 系ショートカット
--   ⌥ (Windows の Win の位置)  → Win 系ショートカット
--   ⌘ (Windows の Alt の位置)  → Alt+Tab / Alt+F4
--
-- 機能:
--   1. ⌃C/V/X/Z/Y/A/S/F 等を ⌘ に変換する（除外アプリでは変換しない）
--   2. Home/End → 行頭/行末、⌃←/→ → 単語移動、⌃Backspace → 単語削除
--   3. ⌘Tab → ウィンドウ単位の切替、⌘F4 → ウィンドウを閉じる
--   4. ⌥←/→/↑ → 左半分/右半分/最大化、⌥↓ → 元のサイズに戻す（戻す対象がなければ最小化）
--   5. ⌥D → デスクトップ表示の切替、⌥E → Finder、⌥L → 画面ロック、⌥R → ファイル名を指定して実行
--   6. Finder: Enter → 開く、F2 → 名前の変更、Delete → ゴミ箱へ移動、Backspace → 戻る、
--      ⌃X → ⌃V で移動
--   7. PrintScreen → 全画面をクリップボードへ、⌥⇧S → 範囲を選択してクリップボードへ
--   8. ⌥/ → キー対応表の表示（初回の読み込み時にも表示する）
--   9. ⌘` → 英数とかなの切替
--  10. ⌥V → クリップボード履歴から選択して貼り付け
--  11. ⌃⇧Esc → アクティビティモニタ、⌃⌘Delete → 強制終了ダイアログ
--  12. ⌥1〜⌥9 → TASKBAR_APPS のアプリを起動・前面化（前面のアプリではウィンドウを巡回）
--  13. マウスホイールのスクロール方向を反転する（トラックパッドは対象外）
--  14. F5 → 再読み込み（⌘R）、F11 → フルスクリーンの切替
--  15. メニューバーの Win 表示のクリック、または ⌃⌥⌘W で有効/無効を切り替える
--
-- 設定変更後は Hammerspoon コンソールで hs.reload() を実行する。
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- Ctrl 系の変換（機能 1, 2, 6, F5）の対象外とするアプリの bundle ID。
-- ⌃ 付きのキーに固有の機能を割り当てているアプリを登録する。
-- Win 系（⌥）のショートカットは、ここに登録したアプリでも有効である。
local EXCLUDE_APPS = {
  ["com.apple.Terminal"]          = true,
  ["com.googlecode.iterm2"]       = true,
  ["com.cmuxterm.app"]            = true,
  ["com.mitchellh.ghostty"]       = true,
  ["dev.warp.Warp-Stable"]        = true,
  ["net.kovidgoyal.kitty"]        = true,
  ["com.github.wez.wezterm"]      = true,
  ["org.alacritty"]               = true,
}

-- ⌃+キー を ⌘+キー に変換する対象。値で変換後のキーと ⇧ の付加を指定できる。
-- ⌃⇧+キー は ⌘⇧+キー に変換する。
local CTRL_TO_CMD = {
  a = {}, c = {}, v = {}, x = {}, z = {},
  s = {}, f = {}, n = {}, o = {}, p = {},
  w = {}, t = {}, r = {}, l = {},
  b = {}, i = {}, u = {},
  y = { key = "z", shift = true },  -- やり直し: Ctrl+Y → ⌘⇧Z
}

-- ⌥1〜⌥9 に割り当てるアプリ（タスクバーのピン留めに相当）。上から順に ⌥1, ⌥2, … となる。
-- bundleIDs を上から順に試し、見つからなければ name（アプリ名）で起動する。
local TASKBAR_APPS = {
  { name = "Finder",             bundleIDs = { "com.apple.finder" } },
  { name = "Microsoft Edge",     bundleIDs = { "com.microsoft.edgemac", "com.google.Chrome", "com.apple.Safari" } },
  { name = "Microsoft Outlook",  bundleIDs = { "com.microsoft.Outlook", "com.apple.mail" } },
  { name = "Microsoft Teams",    bundleIDs = { "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap" } },
  { name = "Microsoft Word",     bundleIDs = { "com.microsoft.Word" } },
  { name = "Microsoft Excel",    bundleIDs = { "com.microsoft.Excel" } },
  { name = "Microsoft PowerPoint", bundleIDs = { "com.microsoft.Powerpoint" } },
  { name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  { name = "Terminal",           bundleIDs = { "com.apple.Terminal" } },
}

-- クリップボード履歴の保持件数
local CLIP_MAX = 20

-- マウスホイールのスクロール方向を反転するか。macOS のナチュラルスクロールが有効な場合のみ反転する。
local REVERSE_MOUSE_SCROLL = true

-- 有効/無効を切り替えるホットキー
local TOGGLE_MODS, TOGGLE_KEY = { "ctrl", "alt", "cmd" }, "w"

-- 読み込み時に有効にするか
local ENABLED_ON_START = true

-- キー対応表を初回の読み込み時に表示するか
local SHOW_CHEATSHEET_ON_FIRST_LOAD = true

-- キー対応表の表示秒数
local CHEATSHEET_SECONDS = 10

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

local K = hs.keycodes.map
local FINDER = "com.apple.finder"

-- ローカル変数からのみ参照されるオブジェクトは GC で回収され、
-- eventtap やホットキーが停止する。グローバルな表に保持して回収を防ぐ。
WinCompat = WinCompat or {}
local M = WinCompat

-- イベントのコールバック内で時間のかかる処理を行うと、macOS が eventtap を無効化する。
-- ウィンドウ操作などはコールバックの外で実行する。
local function defer(fn)
  hs.timer.doAfter(0, fn)
end

-- ---------------------------------------------------------------------
-- 最前面アプリの記録
-- ---------------------------------------------------------------------
-- キー入力ごとに最前面アプリを問い合わせる処理を避けるため、
-- アプリ切替時に bundle ID を記録し、キー変換ではその値を参照する。
local function currentBundleID()
  local app = hs.application.frontmostApplication()
  return app and app:bundleID()
end

M.frontBundleID = currentBundleID()
M.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated then
    M.frontBundleID = app and app:bundleID()
  end
end)

-- ---------------------------------------------------------------------
-- 4. ウィンドウのスナップ（⌥+矢印）
-- ---------------------------------------------------------------------
-- スナップ前のフレームをウィンドウ ID ごとに保持し、⌥↓ で元に戻す。
M.savedFrames = M.savedFrames or {}

local function snap(fraction)
  local win = hs.window.focusedWindow()
  if not win then return end
  local id = win:id()
  if id and not M.savedFrames[id] then M.savedFrames[id] = win:frame() end
  local f = win:screen():frame()  -- メニューバーと Dock を除いた作業領域
  win:setFrame({
    x = f.x + f.w * fraction.x,
    y = f.y + f.h * fraction.y,
    w = f.w * fraction.w,
    h = f.h * fraction.h,
  }, 0)
end

local function restoreOrMinimize()
  local win = hs.window.focusedWindow()
  if not win then return end
  local saved = win:id() and M.savedFrames[win:id()]
  if saved then
    win:setFrame(saved, 0)
    M.savedFrames[win:id()] = nil
  else
    win:minimize()
  end
end

-- ---------------------------------------------------------------------
-- 5. Win 系のショートカット
-- ---------------------------------------------------------------------
-- Win+D 相当: 表示中のアプリを隠す。再度押すと、隠したアプリを再表示する。
-- 最小化ではなく非表示を用いるのは、アニメーションを伴わず即座に切り替わるためである。
M.hiddenByDesktop = nil

local function toggleDesktop()
  if M.hiddenByDesktop then
    for _, app in ipairs(M.hiddenByDesktop) do
      if app:isRunning() then app:unhide() end
    end
    M.hiddenByDesktop = nil
    return
  end

  local hidden = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 and not app:isHidden() and app:bundleID() ~= FINDER
        and #app:visibleWindows() > 0 then
      app:hide()
      hidden[#hidden + 1] = app
    end
  end
  M.hiddenByDesktop = hidden
end

-- Win+E 相当: ホームフォルダを新しい Finder ウィンドウで開く。
local function openFinder()
  hs.task.new("/usr/bin/open", nil, { os.getenv("HOME") }):start()
end

-- Win+R 相当: 入力した名前のアプリを起動する。アプリとして開けない場合は、
-- パスまたは URL として開く。
local function runCommand(query)
  if not query or query == "" then return end
  hs.task.new("/usr/bin/open", function(code)
    if code ~= 0 then
      hs.task.new("/usr/bin/open", function(code2)
        if code2 ~= 0 then hs.alert.show("開けない: " .. query) end
      end, { query }):start()
    end
  end, { "-a", query }):start()
end

M.runChooser = hs.chooser.new(function(choice)
  if choice then runCommand(choice.query) end
end)
M.runChooser:placeholderText("ファイル名を指定して実行（アプリ名・パス・URL）")
M.runChooser:queryChangedCallback(function(q)
  M.runChooser:choices(q ~= "" and { { text = "実行: " .. q, query = q } } or {})
end)

local function showRunDialog()
  M.runChooser:query("")
  M.runChooser:show()
end

-- ---------------------------------------------------------------------
-- 7. スクリーンショット
-- ---------------------------------------------------------------------
-- macOS は合成したキー入力によるスクリーンショットのショートカットを受け付けない場合があるため、
-- screencapture コマンドを直接実行する。-c はクリップボードへの保存を表す。
local function capture(args)
  hs.task.new("/usr/sbin/screencapture", nil, args):start()
end

-- ---------------------------------------------------------------------
-- 9. 英数 / かな の切替
-- ---------------------------------------------------------------------
-- 入力ソースの ID は IME により異なるため、英数キー・かなキーのイベントを送出して切り替える。
-- hs.keycodes.currentMethod() は入力メソッド（日本語入力など）の使用中のみ値を返す。
local KEY_EISU, KEY_KANA = 102, 104

local function toggleIME()
  hs.eventtap.keyStroke({}, hs.keycodes.currentMethod() and KEY_EISU or KEY_KANA, 0)
end

-- ---------------------------------------------------------------------
-- 10. クリップボード履歴
-- ---------------------------------------------------------------------
-- 履歴は hs.settings に保存し、Hammerspoon の再起動後も保持する。
local CLIP_KEY = "WinCompat.clipHistory"
M.clipHistory = hs.settings.get(CLIP_KEY) or {}

-- パスワードマネージャ等が記録対象外であることを示すために付ける型
local function isConcealed()
  for _, t in ipairs(hs.pasteboard.contentTypes() or {}) do
    if t == "org.nspasteboard.ConcealedType" or t == "org.nspasteboard.TransientType" then return true end
  end
  return false
end

M.clipWatcher = hs.pasteboard.watcher.new(function(text)
  if not text or text == "" or isConcealed() then return end
  for i, v in ipairs(M.clipHistory) do
    if v == text then table.remove(M.clipHistory, i) break end   -- 重複は先頭へ移動する
  end
  table.insert(M.clipHistory, 1, text)
  while #M.clipHistory > CLIP_MAX do table.remove(M.clipHistory) end
  hs.settings.set(CLIP_KEY, M.clipHistory)
end)

-- chooser を閉じた直後は元のアプリへのフォーカスの移動が完了していないため、待機してから貼り付ける。
M.clipChooser = hs.chooser.new(function(choice)
  if not choice then return end
  hs.pasteboard.setContents(choice.full)
  hs.timer.doAfter(0.1, function() hs.eventtap.keyStroke({ "cmd" }, "v", 0) end)
end)

local function showClipHistory()
  local items = {}
  for _, t in ipairs(M.clipHistory) do
    items[#items + 1] = { text = t:gsub("%s+", " "):sub(1, 80), full = t }
  end
  M.clipChooser:choices(items)
  M.clipChooser:show()
end

-- ---------------------------------------------------------------------
-- 11. タスクマネージャ / 強制終了
-- ---------------------------------------------------------------------
local function openActivityMonitor()
  hs.application.launchOrFocusByBundleID("com.apple.ActivityMonitor")
end

local function openForceQuit()
  hs.eventtap.keyStroke({ "cmd", "alt" }, "escape", 0)
end

-- ---------------------------------------------------------------------
-- 12. タスクバー相当のアプリ起動（⌥1〜⌥9）
-- ---------------------------------------------------------------------
local function runningApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    local app = hs.application.get(id)
    if app then return app end
  end
  return hs.application.get(spec.name)
end

local function launchApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    if hs.application.launchOrFocusByBundleID(id) then return end
  end
  if not hs.application.launchOrFocus(spec.name) then
    hs.alert.show("起動できない: " .. spec.name)
  end
end

-- 前面のアプリであれば、そのアプリの次のウィンドウ（ウィンドウ ID 順）へ移動する。
local function focusTaskbarApp(spec)
  local app = runningApp(spec)
  if not app then return launchApp(spec) end

  local front = hs.application.frontmostApplication()
  if not (front and front:pid() == app:pid()) then
    app:activate()
    return
  end

  local wins = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then wins[#wins + 1] = w end
  end
  if #wins < 2 then return end
  table.sort(wins, function(a, b) return a:id() < b:id() end)
  local current = hs.window.focusedWindow()
  local idx = 0
  for i, w in ipairs(wins) do
    if current and w:id() == current:id() then idx = i break end
  end
  wins[idx % #wins + 1]:focus()
end

-- ---------------------------------------------------------------------
-- 13. マウスホイールのスクロール方向
-- ---------------------------------------------------------------------
-- トラックパッドとマジックマウスのスクロールは連続値（isContinuous = 1）として届く。
-- 連続値でないイベント（ホイールマウス）のみ、縦横の移動量の符号を反転する。
local P = hs.eventtap.event.properties
local SCROLL_AXES = {
  P.scrollWheelEventDeltaAxis1, P.scrollWheelEventDeltaAxis2,
  P.scrollWheelEventPointDeltaAxis1, P.scrollWheelEventPointDeltaAxis2,
  P.scrollWheelEventFixedPtDeltaAxis1, P.scrollWheelEventFixedPtDeltaAxis2,
}

M.scrollTap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(e)
  if e:getProperty(P.scrollWheelEventIsContinuous) ~= 0 then return false end
  for _, axis in ipairs(SCROLL_AXES) do
    e:setProperty(axis, -e:getProperty(axis))
  end
  return false
end)

local function shouldReverseScroll()
  return REVERSE_MOUSE_SCROLL and hs.mouse.scrollDirection() == "natural"
end

-- ---------------------------------------------------------------------
-- 14. F11（フルスクリーン）
-- ---------------------------------------------------------------------
local function toggleFullScreen()
  local win = hs.window.focusedWindow()
  if win then win:toggleFullScreen() end
end

-- ---------------------------------------------------------------------
-- 8. キー対応表
-- ---------------------------------------------------------------------
local CHEATSHEET = table.concat({
  "Windows互換モード キー対応表",
  "",
  "Ctrl+C / V / X / Z / Y   ⌃C / V / X / Z / Y",
  "Ctrl+← / →             ⌃← / →（単語移動）",
  "Home / End              Home / End",
  "Alt+Tab / Alt+F4        ⌘Tab / ⌘F4",
  "Win+← / → / ↑ / ↓       ⌥← / → / ↑ / ↓",
  "Win+D / E / L / R       ⌥D / E / L / R",
  "PrintScreen / Win+⇧+S   PrintScreen / ⌥⇧S",
  "Win+V / Win+1〜9        ⌥V / ⌥1〜9",
  "Alt+` / Ctrl+Shift+Esc   ⌘` / ⌃⇧Esc",
  "Ctrl+Alt+Del            ⌃⌘Delete",
  "F5 / F11                F5 / F11",
  "",
  "⌥/ 対応表   ⌃⌥⌘W 有効/無効",
}, "\n")

local function toggleCheatsheet()
  if M.cheatsheetAlert then
    hs.alert.closeSpecific(M.cheatsheetAlert)
    M.cheatsheetAlert = nil
    return
  end
  local id = hs.alert.show(CHEATSHEET, {
    textFont = "Menlo", textSize = 16, radius = 8,
  }, hs.screen.mainScreen(), CHEATSHEET_SECONDS)
  M.cheatsheetAlert = id
  hs.timer.doAfter(CHEATSHEET_SECONDS, function()
    if M.cheatsheetAlert == id then M.cheatsheetAlert = nil end
  end)
end

-- ---------------------------------------------------------------------
-- キー変換（eventtap）
-- ---------------------------------------------------------------------
-- keyDown ごとに処理を決め、同じキーの keyUp にも同じ処理を適用する。
-- 処理は次の3種類である。
--   nil                         そのまま通過させる
--   { consume = true }          イベントを破棄する（ショートカットとして処理済み）
--   { code = ..., flags = ... } キーコードと修飾キーを書き換えて通過させる
-- 書き換えたイベントはこの関数に再入しない。

-- ⌥（Win キー）のショートカット
local WIN_ACTIONS = {
  [K.left]  = function() snap({ x = 0,   y = 0, w = 0.5, h = 1 }) end,
  [K.right] = function() snap({ x = 0.5, y = 0, w = 0.5, h = 1 }) end,
  [K.up]    = function() snap({ x = 0,   y = 0, w = 1,   h = 1 }) end,
  [K.down]  = restoreOrMinimize,
  [K.d]     = toggleDesktop,
  [K.e]     = openFinder,
  [K.l]     = function() hs.caffeinate.lockScreen() end,
  [K.r]     = showRunDialog,
  [K["/"]]  = toggleCheatsheet,
  [K.v]     = showClipHistory,
}
for i, spec in ipairs(TASKBAR_APPS) do
  if i > 9 then break end
  WIN_ACTIONS[K[tostring(i)]] = function() focusTaskbarApp(spec) end
end
-- ⌥⇧（Win+Shift）のショートカット
local WIN_SHIFT_ACTIONS = {
  [K.s] = function() capture({ "-i", "-c" }) end,  -- 範囲選択
}
local PRINT_SCREEN = K.f13  -- Windows キーボードの PrintScreen は macOS では F13 として届く

-- keycode → Ctrl 変換ルール
local ctrlRules = {}
for key, rule in pairs(CTRL_TO_CMD) do
  ctrlRules[K[key]] = { code = K[rule.key or key], shift = rule.shift }
end

-- 複数の設定を組み合わせて導入した場合（ルートの install.sh）、eventtap で処理するキーを
-- loader.lua に登録し、他の設定とキーが重複していれば起動時に警告されるようにする。
-- hs.hotkey で割り当てたキーは loader.lua が自動で記録する。
if HSVariants then
  local claim = HSVariants.claim
  for code in pairs(WIN_ACTIONS) do claim({ "alt" }, code) end
  for code in pairs(WIN_SHIFT_ACTIONS) do claim({ "alt", "shift" }, code) end
  for code in pairs(ctrlRules) do
    claim({ "ctrl" }, code)
    claim({ "ctrl", "shift" }, code)
  end
  for _, code in ipairs({ K.left, K.right, K.home, K["end"] }) do
    claim({ "ctrl" }, code)
    claim({ "ctrl", "shift" }, code)
  end
  claim({ "ctrl" }, K.delete)
  claim({}, PRINT_SCREEN)
  claim({}, K.f5)
  claim({}, K.f11)
  claim({ "cmd" }, K["`"])
  claim({ "ctrl", "shift" }, K.escape)
  claim({ "ctrl", "cmd" }, K.delete)
  claim({ "ctrl", "cmd" }, K.forwarddelete)
end

local CONSUME = { consume = true }

-- macOS が fn フラグ付きで送出するキー。書き換え後のキーに合わせて fn フラグを設定する。
local FN_KEYS = {
  [K.left] = true, [K.right] = true, [K.up] = true, [K.down] = true,
  [K.home] = true, [K["end"]] = true, [K.forwarddelete] = true,
}

local function to(code, flags) return { code = code, flags = flags } end

-- フォーカスが文字入力欄（Finder の名前の変更中など）にあるか
local function isEditingText()
  local el = hs.uielement.focusedElement()
  local role = el and el:role()
  return role == "AXTextField" or role == "AXTextArea"
end

-- 6. Finder 固有の処理。対象外であれば nil を返す。
local function finderRule(code, f)
  local plain = not f.ctrl and not f.cmd and not f.alt and not f.shift
  if plain and (code == K["return"] or code == K.f2 or code == K.forwarddelete
                or code == K.delete) then
    if isEditingText() then return nil end
    if code == K["return"]     then return to(K.down, { cmd = true }) end    -- 開く
    if code == K.f2            then return to(K["return"], {}) end          -- 名前の変更
    if code == K.forwarddelete then return to(K.delete, { cmd = true }) end  -- ゴミ箱へ移動
    if code == K.delete        then return to(K["["], { cmd = true }) end    -- 戻る
  end

  -- 切り取りと貼り付けによる移動。Finder の ⌘X はファイルに作用しないため、
  -- ⌃X はコピーとして扱い、続く ⌃V を移動（⌘⌥V）に変換する。
  if f.ctrl and not f.cmd and not f.alt and not f.shift and not isEditingText() then
    if code == K.x then
      M.finderCut = true
      return to(K.c, { cmd = true })
    end
    if code == K.c then M.finderCut = false end
    if code == K.v and M.finderCut then
      M.finderCut = false
      return to(K.v, { cmd = true, alt = true })
    end
  end
  return nil
end

local function decide(code, f, isRepeat)
  -- Win 系（⌥ のみ、または ⌥⇧）
  if f.alt and not f.ctrl and not f.cmd then
    local action = (f.shift and WIN_SHIFT_ACTIONS or WIN_ACTIONS)[code]
    if action then
      if not isRepeat then defer(action) end
      return CONSUME
    end
  end

  -- 除外アプリでも有効なショートカット
  local global
  local noMods = not f.ctrl and not f.cmd and not f.alt
  if code == PRINT_SCREEN and noMods then
    global = function() capture({ "-c" }) end
  elseif code == K.f11 and noMods and not f.shift then
    global = toggleFullScreen
  elseif code == K["`"] and f.cmd and not f.ctrl and not f.alt and not f.shift then
    global = toggleIME                                                  -- Alt+`
  elseif code == K.escape and f.ctrl and f.shift and not f.cmd and not f.alt then
    global = openActivityMonitor                                        -- Ctrl+Shift+Esc
  elseif (code == K.delete or code == K.forwarddelete)
      and f.ctrl and f.cmd and not f.alt and not f.shift then
    global = openForceQuit                                              -- Ctrl+Alt+Del
  end
  if global then
    if not isRepeat then defer(global) end
    return CONSUME
  end

  local bundleID = M.frontBundleID
  if EXCLUDE_APPS[bundleID] then return nil end

  if code == K.f5 and noMods and not f.shift then
    return to(K.r, { cmd = true })                                      -- 再読み込み
  end

  if bundleID == FINDER then
    local rule = finderRule(code, f)
    if rule then return rule end
  end

  local shift = f.shift or nil

  -- ⌃ のみ（⇧ の併用は可）
  if f.ctrl and not f.cmd and not f.alt then
    local rule = ctrlRules[code]
    if rule then return to(rule.code, { cmd = true, shift = shift or rule.shift }) end
    if code == K.left or code == K.right then return to(code, { alt = true, shift = shift }) end
    if code == K.delete then return to(code, { alt = true }) end                     -- 単語削除
    if code == K.home   then return to(K.up, { cmd = true, shift = shift }) end      -- 文書の先頭
    if code == K["end"] then return to(K.down, { cmd = true, shift = shift }) end    -- 文書の末尾
    return nil
  end

  -- 修飾キーなし（⇧ の併用は可）の Home/End → 行頭/行末
  if not f.ctrl and not f.cmd and not f.alt then
    if code == K.home   then return to(K.left, { cmd = true, shift = shift }) end
    if code == K["end"] then return to(K.right, { cmd = true, shift = shift }) end
  end

  return nil
end

M.decisions = {}  -- keycode → keyDown 時に決めた処理

local function apply(e, d)
  if not d then return false end
  if d.consume then return true end   -- true: イベントを破棄する
  local flags = {}
  for k, v in pairs(d.flags) do flags[k] = v end
  flags.fn = FN_KEYS[d.code]
  e:setKeyCode(d.code)
  e:setFlags(flags)
  return false                        -- false: 書き換えたイベントを通過させる
end

local function onKey(e)
  local code = e:getKeyCode()

  if e:getType() == hs.eventtap.event.types.keyUp then
    local d = M.decisions[code]
    M.decisions[code] = nil
    return apply(e, d)
  end

  local isRepeat = e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0
  local d = decide(code, e:getFlags(), isRepeat)
  M.decisions[code] = d
  return apply(e, d)
end

M.keyTap = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, onKey)

-- macOS は応答が遅延した eventtap を無効化する。一定間隔で状態を確認し、再開する。
M.tapWatchdog = hs.timer.new(5, function()
  if M.enabled and not M.keyTap:isEnabled() then
    print("[wincompat] eventtap を再開")
    M.keyTap:start()
  end
  if M.enabled and shouldReverseScroll() and not M.scrollTap:isEnabled() then
    M.scrollTap:start()
  end
end)

-- ---------------------------------------------------------------------
-- 3. Alt+Tab / Alt+F4（物理位置に合わせて ⌘Tab / ⌘F4 に割り当てる）
-- ---------------------------------------------------------------------
-- hs.window.switcher は修飾キーを離した時点で選択中のウィンドウに切り替える。
M.switcher = hs.window.switcher.new()
M.switcher.ui.showThumbnails = false
M.switcher.ui.showSelectedThumbnail = false

-- Alt+F4 相当: ウィンドウを閉じる。アプリの最後のウィンドウであればアプリを終了する。
local function closeLikeWindows()
  local win = hs.window.focusedWindow()
  if not win then return end
  local app = win:application()

  local count = 0
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then count = count + 1 end
  end

  -- Finder は終了の対象外とする（デスクトップ表示を担うため）
  if count <= 1 and app:bundleID() ~= FINDER then
    app:kill()   -- 通常の終了（⌘Q 相当）。強制終了は kill9()
  else
    win:close()
  end
end

local function nextWin() M.switcher:next() end
local function prevWin() M.switcher:previous() end

M.hotkeys = {
  hs.hotkey.new({ "cmd" },          "tab", nextWin, nil, nextWin),
  hs.hotkey.new({ "cmd", "shift" }, "tab", prevWin, nil, prevWin),
  hs.hotkey.new({ "cmd" },          "f4",  closeLikeWindows),
}

-- ---------------------------------------------------------------------
-- 15. 有効 / 無効の切替
-- ---------------------------------------------------------------------
M.menubar = M.menubar or hs.menubar.new()

local function setEnabled(on)
  M.enabled = on
  M.decisions = {}
  if on then
    M.keyTap:start()
    M.tapWatchdog:start()
    M.appWatcher:start()
    M.frontBundleID = currentBundleID()
    M.clipWatcher:start()
    if shouldReverseScroll() then M.scrollTap:start() end
    for _, hk in ipairs(M.hotkeys) do hk:enable() end
  else
    M.keyTap:stop()
    M.clipWatcher:stop()
    M.scrollTap:stop()
    M.tapWatchdog:stop()
    M.appWatcher:stop()
    for _, hk in ipairs(M.hotkeys) do hk:disable() end
  end

  if M.menubar then
    M.menubar:setTitle(on and "Win" or "Mac")
    M.menubar:setTooltip(on and "Windows互換: 有効（クリックで無効化）"
                              or "Windows互換: 無効（クリックで有効化）")
  end
  hs.alert.show(on and "Windows互換: 有効" or "Windows互換: 無効")
end

local function toggle() setEnabled(not M.enabled) end

if M.menubar then M.menubar:setClickCallback(toggle) end
M.toggleHotkey = hs.hotkey.bind(TOGGLE_MODS, TOGGLE_KEY, toggle)

setEnabled(ENABLED_ON_START)

-- 初回の読み込み時のみ対応表を表示する（表示済みであることを hs.settings に記録する）
if SHOW_CHEATSHEET_ON_FIRST_LOAD and not hs.settings.get("WinCompat.cheatsheetShown") then
  hs.settings.set("WinCompat.cheatsheetShown", true)
  hs.timer.doAfter(1, toggleCheatsheet)
end
