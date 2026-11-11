#!/bin/sh
# hammerspoon-variants のインストール / アンインストール
#   ./install.sh                                 一覧から番号で選んで導入する
#   ./install.sh windows-compat window-manager   指定した設定を組み合わせて導入する（1つでもよい）
#   ./install.sh --list                          導入できる設定の一覧を表示する
#   ./install.sh --uninstall                     導入前の init.lua に戻す
#
# ~/.hammerspoon/init.lua には、選んだ設定を loader.lua 経由で読み込む数行のファイルを生成する。
# 導入前の init.lua は init.lua.before-variants に退避する。選び直すときは再実行するだけでよい。
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.hammerspoon/init.lua"
BAK="$HOME/.hammerspoon/init.lua.before-variants"
MARK="-- hammerspoon-variants: install.sh が生成したファイル"

reload() {
  # Hammerspoon が起動中かつ hs コマンドが利用可能な場合は、設定を再読み込みする。
  # hs コマンドは今読み込まれている設定が hs.ipc を有効にしている場合だけ接続できる。
  # 初めて導入するときは元の設定が hs.ipc を使っていないことが多いため、失敗したら手動での再読み込みを案内する。
  # hs.reload() は応答を返す前に設定を読み直すため、終了コードは成否の判定に使えない。接続できるかを先に確かめる。
  if command -v hs >/dev/null 2>&1 && pgrep -q Hammerspoon \
     && hs -c 'return 1' >/dev/null 2>&1; then
    hs -c 'hs.reload()' >/dev/null 2>&1 || true
    echo "Hammerspoon の設定を再読み込みした。"
  else
    echo "Hammerspoon の設定を再読み込みすること（メニューバーの Hammerspoon アイコン → Reload Config、"
    echo "またはコンソールで hs.reload()）。"
  fi
}

# variants/ 配下で init.lua を持つディレクトリを設定として扱う
variants() {
  for d in "$ROOT"/variants/*/; do
    [ -f "$d/init.lua" ] && basename "$d"
  done
}

# README.md の見出しを設定の説明として表示する
title() {
  sed -n 's/^# //p' "$ROOT/variants/$1/README.md" 2>/dev/null | head -n 1
}

list() {
  i=0
  for v in $(variants); do
    i=$((i + 1))
    printf '  %d) %-16s %s\n' "$i" "$v" "$(title "$v")"
  done
}

is_generated() {
  [ -f "$DST" ] && [ "$(head -n 1 "$DST")" = "$MARK" ]
}

case "${1:-}" in
  --list)
    list
    exit 0
    ;;
  --uninstall)
    if is_generated; then
      rm "$DST"
      echo "remove : $DST"
    fi
    if [ -e "$BAK" ] || [ -L "$BAK" ]; then
      mv "$BAK" "$DST"
      echo "restore: $BAK -> $DST"
    fi
    reload
    exit 0
    ;;
  -h|--help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

# 引数がなければ番号で選ばせる
if [ $# -eq 0 ]; then
  echo "導入する設定の番号を入力する（複数はスペース区切り、例: 1 2）"
  list
  printf '> '
  read -r answer
  set --
  for n in $answer; do
    case "$n" in
      ''|*[!0-9]*) echo "番号で入力すること: $n" >&2; exit 1 ;;
    esac
    v="$(variants | sed -n "${n}p")"
    if [ -z "$v" ]; then
      echo "番号 $n に該当する設定がない。" >&2
      exit 1
    fi
    set -- "$@" "$v"
  done
  if [ $# -eq 0 ]; then
    echo "設定が選ばれていない。" >&2
    exit 1
  fi
fi

# 名前の確認と重複の除去
selected=""
for v in "$@"; do
  if [ ! -f "$ROOT/variants/$v/init.lua" ]; then
    echo "設定 $v がない。./install.sh --list で一覧を確認すること。" >&2
    exit 1
  fi
  case " $selected " in
    *" $v "*) ;;
    *) selected="$selected $v" ;;
  esac
done

mkdir -p "$(dirname "$DST")"

# 既存の設定を退避する。退避先が存在する場合は上書きせず中断し、導入前の設定を保護する
if ! is_generated && { [ -e "$DST" ] || [ -L "$DST" ]; }; then
  if [ -e "$BAK" ] || [ -L "$BAK" ]; then
    echo "退避先 $BAK が既に存在する。--uninstall を実行するか、内容を確認すること。" >&2
    exit 1
  fi
  mv "$DST" "$BAK"
  echo "backup : $DST -> $BAK"
fi

# パスに引用符が含まれても壊れないよう、Lua の長い文字列 [==[ ]==] で埋め込む
TMP="$DST.tmp.$$"
{
  echo "$MARK"
  echo "-- 読み込む設定を変えるときは、このファイルを編集せず install.sh を再実行する。"
  echo "-- リポジトリを移動した場合も install.sh の再実行が必要である。"
  echo "dofile([==[$ROOT/loader.lua]==]).load({"
  for v in $selected; do
    echo "  \"$v\","
  done
  echo "})"
} > "$TMP"
mv "$TMP" "$DST"

echo "write  : ${DST}（${selected# }）"
reload
