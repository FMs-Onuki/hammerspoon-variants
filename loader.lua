-- =====================================================================
-- hammerspoon-variants ローダー
-- =====================================================================
-- variants/ 配下の設定のうち、選んだものだけを読み込む。
-- ~/.hammerspoon/init.lua は install.sh が生成し、次の形でこのファイルを呼び出す。
--
--   dofile("/path/to/hammerspoon-variants/loader.lua").load({ "windows-compat", "tiling-wm" })
--
-- 読み込み中に登録されたホットキーを設定ごとに記録し、同じキーを複数の設定が使っていれば
-- 起動時に警告する。設定から参照できるよう、グローバルな表 HSVariants に次を用意する。
--   HSVariants.has(name)         name の設定を一緒に読み込むか（読み込み順に関係なく判定できる）
--   HSVariants.claim(mods, key)  hs.hotkey 以外（eventtap 等）で使うキーを登録する
-- =====================================================================

-- install.sh が hs コマンドで設定を再読み込みできるよう、コマンドラインからの接続を受け付ける
pcall(require, "hs.ipc")

local ROOT = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

HSVariants = {
  root      = ROOT,
  selected  = {},  -- name → true（読み込む設定）
  loaded    = {},  -- 読み込みに成功した設定名（読み込み順）
  owners    = {},  -- キーの識別子 → 最初に使った設定名
  conflicts = {},  -- { key = 表示名, owners = { 設定名, ... } }
}
local V = HSVariants

function V.has(name)
  return V.selected[name] == true
end

-- ---------------------------------------------------------------------
-- キーの正規化
-- ---------------------------------------------------------------------
-- hs.hotkey は修飾キーを表（{ "cmd", "alt" }）でも文字列（"⌘⌥" / "cmd-alt"）でも受け付ける。
-- 表記が違っても同じキーと判定できるよう、順序を固定した識別子に変換する。
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd", "fn" }
local MOD_SYMBOL = { ctrl = "⌃", alt = "⌥", shift = "⇧", cmd = "⌘", fn = "fn" }
local MOD_ALIASES = {
  ctrl  = { "ctrl", "control", "⌃" },
  alt   = { "alt", "option", "opt", "⌥" },
  shift = { "shift", "⇧" },
  cmd   = { "cmd", "command", "⌘" },
  fn    = { "fn" },
}

local function modSet(mods)
  local set = {}
  if type(mods) == "table" then
    for _, m in ipairs(mods) do
      m = tostring(m):lower()
      for name, aliases in pairs(MOD_ALIASES) do
        for _, a in ipairs(aliases) do
          if m == a then set[name] = true end
        end
      end
    end
  elseif type(mods) == "string" then
    local s = mods:lower()
    for name, aliases in pairs(MOD_ALIASES) do
      for _, a in ipairs(aliases) do
        if s:find(a, 1, true) then set[name] = true end
      end
    end
  end
  return set
end

local function keyName(key)
  if type(key) == "number" then
    return (hs.keycodes.map[key] or tostring(key)):lower()
  end
  return tostring(key):lower()
end

local function keyId(mods, key)
  local set, symbols = modSet(mods), {}
  for _, m in ipairs(MOD_ORDER) do
    if set[m] then symbols[#symbols + 1] = MOD_SYMBOL[m] end
  end
  local name = keyName(key)
  local label = table.concat(symbols) .. (#name == 1 and name:upper() or name)
  return table.concat(symbols, "+") .. "|" .. name, label
end

-- ---------------------------------------------------------------------
-- キーの登録と重複の検知
-- ---------------------------------------------------------------------
local current  -- 読み込み中の設定名

function V.claim(mods, key)
  if not current then return end
  local id, label = keyId(mods, key)
  local owner = V.owners[id]
  if not owner then
    V.owners[id] = current
  elseif owner ~= current then
    local c = V.conflicts[id]
    if not c then
      c = { key = label, owners = { owner } }
      V.conflicts[id] = c
    end
    local listed = false
    for _, o in ipairs(c.owners) do listed = listed or o == current end
    if not listed then c.owners[#c.owners + 1] = current end
  end
end

-- 読み込み中だけ hs.hotkey.new / bind を差し替え、登録されたキーを記録する。
-- 読み込み後は元に戻すため、設定の動作には影響しない。
local function withHotkeyTracking(fn)
  local origNew, origBind = hs.hotkey.new, hs.hotkey.bind
  hs.hotkey.new = function(mods, key, ...)
    V.claim(mods, key)
    return origNew(mods, key, ...)
  end
  hs.hotkey.bind = function(mods, key, ...)
    V.claim(mods, key)
    return origBind(mods, key, ...)
  end
  local ok, err = pcall(fn)
  hs.hotkey.new, hs.hotkey.bind = origNew, origBind
  return ok, err
end

-- ---------------------------------------------------------------------
-- 読み込み
-- ---------------------------------------------------------------------
local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

function V.load(names)
  for _, name in ipairs(names) do V.selected[name] = true end

  local errors = {}
  for _, name in ipairs(names) do
    local path = ROOT .. "/variants/" .. name .. "/init.lua"
    if not fileExists(path) then
      errors[#errors + 1] = name .. ": " .. path .. " が見つからない"
    else
      current = name
      -- 1つの設定でエラーが起きても、残りの設定は読み込む
      local ok, err = withHotkeyTracking(function() dofile(path) end)
      current = nil
      if ok then
        V.loaded[#V.loaded + 1] = name
      else
        errors[#errors + 1] = name .. ": " .. tostring(err)
      end
    end
  end

  print("[variants] 読み込み: " .. (#V.loaded > 0 and table.concat(V.loaded, ", ") or "なし"))

  for _, e in ipairs(errors) do print("[variants] エラー: " .. e) end
  if #errors > 0 then
    hs.alert.show("設定の読み込みに失敗した（詳細は Hammerspoon コンソール）\n"
                  .. table.concat(errors, "\n"), 8)
  end

  local lines = {}
  for _, c in pairs(V.conflicts) do
    lines[#lines + 1] = c.key .. "  " .. table.concat(c.owners, " / ")
  end
  table.sort(lines)
  for _, l in ipairs(lines) do print("[variants] キーの重複: " .. l) end
  if #lines > 0 then
    -- 重複したキーは、後から登録した設定の動作が優先されるか、どちらも動かない場合がある
    hs.alert.show("キーが重複している（" .. #lines .. " 件）。各設定の修飾キーを変更すること。\n"
                  .. table.concat(lines, "\n", 1, math.min(#lines, 8))
                  .. (#lines > 8 and "\n…（残りは Hammerspoon コンソール）" or ""), 8)
  end

  return V
end

return V
