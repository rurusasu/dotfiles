# macOS グローバル Zoom ショートカット設計

## 目的

macOS の標準メニュー項目「Zoom／拡大・縮小」に `Control+Command+M` を割り当て、対象アプリのウインドウをデスクトップ内で最大表示・元のサイズへ戻せるようにする。

## 適用範囲

- 対象OSは macOS のみとする。
- 対象は macOS の全アプリに共通するユーザー設定とする。
- メニュー項目名は英語環境の `Zoom` と日本語環境の `拡大／縮小` の両方を登録する。
- ショートカット表現は macOS の `NSUserKeyEquivalents` 形式 `@^m` を使う。
- アプリが対象メニュー項目を提供しない場合や、メニューショートカットを処理しないアプリでは動作保証しない。

## 実装方針

macOS の nix-darwin 構成 `nix/darwin/default.nix` に独立した activation script を追加する。既存の `raycastHotkey` activation script と同じく、`DOTFILES_USER` のログインユーザーとして `/usr/bin/defaults` を実行する。

実行内容は次の2つである。

```sh
defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
```

`-dict-add` を使うことで、`NSUserKeyEquivalents` 内の既存のメニューショートカットを上書きせず、対象の2項目だけを冪等に設定する。設定後に対象アプリを自動再起動することはしない。

## 変更対象

- `nix/darwin/default.nix`
  - macOS activation にグローバルZoomショートカット設定を追加する。
- `tests/bash/macos_config.bats`
  - activation script の存在、macOSユーザー権限経由の `defaults` 実行、英日メニュー名、`@^m` の設定を契約テストで検証する。
- `docs/chezmoi/keybindings.md`
  - macOSの補助操作としてショートカットと適用条件を記載する。

## 検証

- 追加するBatsテストを単独実行する。
- 既存の `tests/bash/macos_config.bats` を実行する。
- `git diff --check` を実行する。
- Nix が利用可能な環境では、`DOTFILES_USER` と `DOTFILES_HOME` を指定したmacOS構成評価を実行する。

## 利用者への注意

設定反映後、ショートカットを使うアプリを再起動する必要がある。アプリのメニューに「Zoom」または「拡大／縮小」が存在しない場合、この設定だけではウインドウを最大化できない。
