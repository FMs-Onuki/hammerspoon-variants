#!/bin/sh
# install.sh の動作を確認する。
# HOME を一時ディレクトリに差し替えて実行するため、実際の ~/.hammerspoon は変更しない。
#   ./tests/install-test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1))
    printf '  NG   %s\n' "$1"
  fi
}

# 作業用の HOME を作り、そこへリポジトリを複製して install.sh を実行する。
# パスにスペースと括弧を含めて、クローン先がどこでも動くことを併せて確認する。
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
COPY="$WORK/copy dir (test)/hammerspoon-variants"
mkdir -p "$COPY"
(cd "$ROOT" && tar cf - --exclude .git .) | (cd "$COPY" && tar xf -)
HOME="$WORK/home"
export HOME
mkdir -p "$HOME/.hammerspoon"
cd "$COPY" || exit 1

echo "既存の init.lua がある状態で導入する"
echo '-- 利用者の設定' > "$WORK/original.lua"
ln -s "$WORK/original.lua" "$HOME/.hammerspoon/init.lua"
out="$(./install.sh windows-compat window-manager 2>&1)"
rc=$?
check "終了コードが 0 である" "[ $rc -eq 0 ]"
check "導入したことが表示される" "printf '%s' \"\$out\" | grep -q 'write  :'"
check "選んだ設定名が表示される" "printf '%s' \"\$out\" | grep -q 'windows-compat window-manager'"
check "再読み込みの案内まで到達する" "printf '%s' \"\$out\" | grep -q '再読み込み'"
check "退避したものがシンボリックリンクのまま残る" "[ -L \"\$HOME/.hammerspoon/init.lua.before-variants\" ]"
check "複製先のパスを読み込む" "grep -q 'copy dir (test)' \"\$HOME/.hammerspoon/init.lua\""
check "選んだ設定が両方書かれる" "grep -q '\"windows-compat\"' \"\$HOME/.hammerspoon/init.lua\" && grep -q '\"window-manager\"' \"\$HOME/.hammerspoon/init.lua\""

echo "設定を選び直す"
out="$(./install.sh window-manager 2>&1)"
rc=$?
check "終了コードが 0 である" "[ $rc -eq 0 ]"
check "退避したものを上書きしない" "[ \"\$(readlink \"\$HOME/.hammerspoon/init.lua.before-variants\")\" = \"$WORK/original.lua\" ]"
check "選ばなかった設定が外れる" "! grep -q 'windows-compat' \"\$HOME/.hammerspoon/init.lua\""

echo "同じ設定を重ねて指定する"
./install.sh window-manager window-manager >/dev/null 2>&1
check "一度だけ書かれる" "[ \"\$(grep -c '\"window-manager\"' \"\$HOME/.hammerspoon/init.lua\")\" -eq 1 ]"

echo "番号で選ぶ"
out="$(printf '1 2\n' | ./install.sh 2>&1)"
rc=$?
check "終了コードが 0 である" "[ $rc -eq 0 ]"
check "番号の分だけ導入される" "grep -q 'window-manager' \"\$HOME/.hammerspoon/init.lua\" && grep -q 'windows-compat' \"\$HOME/.hammerspoon/init.lua\""

echo "一覧を表示する"
check "--list に設定が並ぶ" "./install.sh --list | grep -q 'windows-compat'"

echo "指定を間違えたときは中断する"
check "ない名前を指定したとき" "! ./install.sh no-such-variant"
check "ない番号を入力したとき" "! printf '99\n' | ./install.sh"
check "番号以外を入力したとき" "! printf 'abc\n' | ./install.sh"
check "何も入力しなかったとき" "! printf '\n' | ./install.sh"
check "中断しても導入済みの設定が壊れない" "head -n 1 \"\$HOME/.hammerspoon/init.lua\" | grep -q 'install.sh が生成した'"

echo "導入前に戻す"
out="$(./install.sh --uninstall 2>&1)"
rc=$?
check "終了コードが 0 である" "[ $rc -eq 0 ]"
check "元の init.lua が戻る" "[ -L \"\$HOME/.hammerspoon/init.lua\" ] && [ \"\$(readlink \"\$HOME/.hammerspoon/init.lua\")\" = \"$WORK/original.lua\" ]"
check "退避したものが残らない" "[ ! -e \"\$HOME/.hammerspoon/init.lua.before-variants\" ]"

echo "init.lua がない状態で導入する"
rm -rf "$HOME/.hammerspoon"
./install.sh windows-compat >/dev/null 2>&1
check "ディレクトリごと作られる" "[ -f \"\$HOME/.hammerspoon/init.lua\" ]"
check "退避するものがないので作られない" "[ ! -e \"\$HOME/.hammerspoon/init.lua.before-variants\" ]"
./install.sh --uninstall >/dev/null 2>&1
check "戻す対象がなければ生成したものを消す" "[ ! -e \"\$HOME/.hammerspoon/init.lua\" ]"

printf '\n成功 %d / 失敗 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
