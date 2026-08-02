# Remove Arc Browser on macOS Design

## Goal

macOS の dotfiles activation 時に、既存の Arc Homebrew cask と Homebrew が管理する Arc の関連ファイルを削除する。Windows の Arc と macOS の Dia には影響させない。

## Design

Homebrew activation 完了後に、macOS のログインユーザー権限で専用スクリプトを実行する。

- `brew list --cask --versions arc` で Arc のインストール有無を確認する。
- インストール済みの場合だけ `brew uninstall --cask --zap arc` を実行する。
- `--zap` は Homebrew の cask 定義に基づき、Arc のアプリ本体・設定・キャッシュ・関連ファイルを削除する。
- Arc 未インストール時は成功扱いにして、activation を妨げない。
- スクリプトは `nix/darwin/default.nix` の Homebrew activation 後に接続する。

`homebrew.onActivation.cleanup` は変更しない。全 cask を対象にせず、削除対象を Arc に限定するためである。手動で作成された Homebrew 管理外のファイルは対象にしない。

## Verification

- スクリプトのシェルテストで、未インストール時の no-op とインストール時の `--zap` 呼び出しを検証する。
- macOS 設定テストで、activation script の接続と zap コマンドを検証する。
- `nix fmt`、関連 Bats、`pre-commit run --all-files`、`git diff --check` を実行する。
