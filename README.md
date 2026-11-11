# hammerspoon-variants

用途別の [Hammerspoon](https://www.hammerspoon.org/) 設定集である。
必要な設定だけを選んで導入でき、複数の設定を組み合わせて使うこともできる。

| 設定 | 対象 | 概要 |
|---|---|---|
| [windows-compat](variants/windows-compat/) | 一時的に Mac を使う Windows ユーザー | Ctrl 系ショートカット・Win キー操作・Alt+Tab などを Windows と同じ位置のキーで使えるようにする |
| [window-manager](variants/window-manager/) | キーボードでアプリとウィンドウを操作したい人 | ⌥+数字でアプリを切り替え、⌥+キーでウィンドウを左右・最大化・グリッド配置・最小化する |

## 導入

1. Hammerspoon をインストールし、アクセシビリティ権限を許可する
   （システム設定 → プライバシーとセキュリティ → アクセシビリティ）。
2. リポジトリのルートで `install.sh` を実行し、使う設定を選ぶ。

```sh
./install.sh                                 # 一覧から番号で選ぶ（例: 1 2 で両方）
./install.sh windows-compat                  # 1つだけ導入
./install.sh windows-compat window-manager   # 組み合わせて導入
./install.sh --list                          # 導入できる設定の一覧
./install.sh --uninstall                     # 導入前の init.lua に戻す
```

`~/.hammerspoon/init.lua` には、選んだ設定を読み込む数行のファイルが作られる。
導入前の `init.lua` は `init.lua.before-variants` に退避される。
選び直すときは、`install.sh` をもう一度実行するだけでよい。リポジトリを移動したときも再実行する。

初めて導入したときは、`install.sh` から Hammerspoon を再読み込みできないことがある。その場合は
メニューバーの Hammerspoon アイコン → Reload Config で再読み込みする。2回目以降は `install.sh` が自動で再読み込みする。

キー割り当てやカスタマイズ方法は、各設定の README.md を参照する。
いずれの設定も macOS のシステム設定は変更しない。Hammerspoon を終了すると、すべての割り当てが解除される。

## 組み合わせたときのキー

- windows-compat と window-manager を組み合わせると、windows-compat が ⌥ を Win キーとして使うため、
  window-manager の修飾キーが ⌥ → ⌃⌥ に変わる（詳細は [window-manager](variants/window-manager/)）。
- 読み込み時に、複数の設定が同じキーを使っていないかを確認する。重複があれば画面に警告が表示され、
  Hammerspoon コンソールに `[variants] キーの重複:` として一覧が出る。各設定の修飾キーやキーを変更して解消する。
- 1つの設定でエラーが起きても、残りの設定は読み込まれる。エラーは画面と Hammerspoon コンソールに表示される。

## ライセンス

[MIT License](LICENSE) で公開する。
