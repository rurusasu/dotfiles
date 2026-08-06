# macOS Homebrew Cask Updates Design

## Goal

`nrs` が nix-darwin の適用だけで完了したように見える状態をなくし、dotfiles で宣言した macOS デスクトップアプリを確実に更新する。

成功条件は次のとおり。

- 通常の versioned cask と、`auto_updates` または `version = :latest` を持つ greedy cask の両方を更新する。
- 大きな cask のダウンロードが一時的に失敗しても最大 3 回再試行する。
- 更新前に起動していたアプリは Homebrew に終了を委譲し、更新後または失敗時に再起動する。
- 更新後に宣言済み cask が古いままなら `nrs` を成功扱いにしない。
- `wezterm@nightly` は既存の専用インストーラーで管理し、一般 cask 更新には混ぜない。
- 初回 bootstrap と再実行の両方で同じ `install.sh` entrypoint を維持する。

## Root Cause

nix-darwin の現在の Homebrew activation は `brew bundle` を 1 回実行する。`homebrew.onActivation.upgrade = true` は暗黙の upgrade 動作に依存しているため、ログには `Fetching ...` しか出ず、どの cask のダウンロードまたは更新で停止したかが分かりにくい。

今回の実行では Docker Desktop の DMG が約 183 MB の `.incomplete` ファイルとして残り、`brew bundle` が upgrade に到達しなかった。`/run/current-system` も古い Brewfile の generation のままであり、`nrs` 全体が完了していない。一方、`brew outdated --cask` は Claude、Docker Desktop、Orca、Visual Studio Code を通常の更新対象として検出している。

さらに `greedyCasks = false` のため、通常の `brew outdated --cask` では Google Chrome のような自動更新型 cask が除外される。したがって、ダウンロードが成功しても全デスクトップアプリの収束条件にはならない。

## Scope

### In scope

- nix-darwin の Homebrew activation を「不足 cask の導入」と「明示的な cask 更新」に分離する。
- 宣言済み cask 名を nix-darwin configuration から取得する。
- cask ごとの prefetch、upgrade、再試行、最終検証を行う shell script を追加する。
- 起動中だったアプリを更新後または失敗時に再起動する。
- `install-macos.sh` の macOS 収束フローに更新処理を追加する。
- Bats で成功、再試行、恒久的失敗、未更新検出、アプリ再起動を検証する。
- macOS 設定契約テストを新しい責務分離へ更新する。

### Out of scope

- Homebrew で管理していない `/Applications` 配下のアプリ更新。
- Mac App Store アプリの更新。
- `wezterm@nightly` の既存 archive layout workaround の廃止。
- Homebrew tap、formula、cask catalog の全面再設計。
- GUI updater や LaunchAgent によるバックグラウンド更新。
- `nrs` 実行中のアプリ作業内容の保存。

## Architecture

### nix-darwin Homebrew activation

`nix/darwin/default.nix` は `homebrew.onActivation.autoUpdate = true` を維持し、tap と cask metadata を更新する。`homebrew.onActivation.upgrade` は `false` に変更し、nix-darwin が生成する `brew bundle --no-upgrade` には不足 cask の導入だけを担当させる。

`greedyCasks = true` に変更し、生成される Brewfile と設定契約に auto-update cask も収束対象であることを明示する。ただし実際の更新は後段の専用スクリプトが `--greedy` を付けて行う。

### `scripts/sh/update-homebrew-casks.sh`

このスクリプトは通常ユーザー権限で実行し、次の責務だけを持つ。

1. `nix eval` で `darwinConfigurations.macos.config.homebrew.casks` の cask 名を改行区切りで取得する。
2. 各宣言済み cask を `brew outdated --cask --greedy` で判定する。
3. 更新対象ごとに `brew fetch --cask` を最大 3 回実行し、未完了ダウンロードを再開する。
4. cask の app artifact が実行中なら、その app path を再起動リストへ記録する。
5. `brew upgrade --cask --greedy` を cask ごとに最大 3 回実行する。アプリ終了は Homebrew の cask artifact 処理に委譲する。
6. 宣言済み cask に outdated が残っていないことを再検査する。
7. trap で、更新前に実行中だったアプリを成功・失敗のどちらでも再起動する。

再試行は初回を含めて 3 回とし、試行間は 2 秒、4 秒の待機とする。cask ごとに処理することで、失敗した cask 名と段階をログへ明示する。

テストでは実マシンの Homebrew や GUI を変更しないように、`BREW_COMMAND`、`NIX_COMMAND`、`OPEN_COMMAND`、`PGREP_COMMAND`、`SLEEP_COMMAND` と cask list override を環境変数で差し替えられるようにする。本番の既定値は macOS の実コマンドと nix-darwin configuration を使う。

### `scripts/sh/install-macos.sh`

macOS の順序を次のようにする。

1. Docker Desktop を停止する。
2. nix-darwin を適用し、不足 cask と Home Manager を収束させる。
3. 専用 cask updater を通常ユーザーとして実行する。
4. Docker Desktop runtime をセットアップまたは再起動する。
5. chezmoi、Hermes、runtime verification を続行する。

cask updater が失敗した場合は `set -e` により Docker、chezmoi、Hermes の後続処理へ進まず、`nrs` を非ゼロで終了する。

## Data Flow

1. `nrs` alias が `~/.dotfiles/install.sh` を起動する。
2. `install.sh` が Apple Silicon macOS を判定し、`install-macos.sh` へ委譲する。
3. nix-darwin が最新 metadata で不足 cask を導入するが、既存 cask の upgrade は行わない。
4. updater が同じ flake configuration から宣言済み cask 名を読み出す。
5. updater が outdated 判定、prefetch、upgrade、検証を cask ごとに実行する。
6. updater が起動中だったアプリを再度開く。
7. 未更新がゼロの場合だけ残りの macOS setup を続行する。

宣言元を `sets.darwinCasks` と shell の二重管理にはしない。updater は評価済み nix-darwin configuration を読むため、cask の追加・削除がそのまま更新対象へ反映される。

## Error Handling

- cask list の評価に失敗した場合は更新対象なしとして扱わず、即座に失敗する。
- `brew fetch` または `brew upgrade` が失敗した場合は、cask 名、処理段階、試行回数を stderr へ出して再試行する。
- 3 回失敗した cask が 1 つでもあれば、他の再起動処理を済ませた後に非ゼロで終了する。
- upgrade command が成功しても cask が outdated のままなら検証失敗にする。
- updater の途中終了でも trap を通じて記録済みアプリの再起動を試みる。再起動失敗は元の更新エラーを隠さない。
- Docker Desktop は既存の `setup_docker_runtime` が起動と engine readiness を保証する。
- `wezterm@nightly` は nix-darwin の cask list から除外済みのため updater 対象にならず、既存の `install-wezterm-nightly.sh` が扱う。

## Testing

### Behavioral Bats tests

`tests/bash/macos_homebrew_cask_update.bats` で fake command を使い、次を検証する。

- 宣言済みで outdated な cask だけを `fetch` と `upgrade --greedy` に渡す。
- fetch が 2 回失敗して 3 回目に成功した場合、upgrade と最終検証まで進む。
- upgrade が 3 回失敗した場合、スクリプトは非ゼロで終了し、cask 名と試行回数を報告する。
- upgrade command 成功後も outdated が残る場合、スクリプトは非ゼロで終了する。
- 更新前に実行中だった app artifact は成功時に再起動する。
- 更新失敗時にも記録済み app artifact の再起動を試みる。
- cask list 評価失敗は「更新なし」と誤認せず失敗する。

### Configuration contract tests

`tests/bash/macos_config.bats` で次を検証する。

- `greedyCasks = true` である。
- `autoUpdate = true` と `upgrade = false` の責務分離になっている。
- `install-macos.sh` が nix-darwin 適用後、Docker runtime 起動前に updater を呼ぶ。
- updater が `wezterm@nightly` を直接管理しない。

### Validation

- updater の Bats test
- `tests/bash/macos_config.bats`
- Bash syntax check と ShellCheck
- `task test:bash DOTFILES_PATH="$PWD"`
- `nix fmt -- --check` 相当の repository formatting check
- `nix eval --impure` による macOS configuration 評価
- 実行前後の `brew outdated --cask --greedy` と `brew bundle check` による macOS smoke test

実 macOS smoke test はアプリを終了するため、実装検証の最後に実行し、Orca を含む作業セッションへの影響を事前に通知する。

## Migration and Rollback

次回の `nrs` から新しい updater が自動実行される。既存の Homebrew installation と Caskroom を再作成せず、outdated cask だけを更新する。残っている `.incomplete` download は Homebrew の fetch に再利用または置換させる。

rollback は `install-macos.sh` から updater 呼び出しを外し、`greedyCasks = false`、`onActivation.upgrade = true` に戻すことで可能。cask 更新自体は通常の Homebrew upgrade なので、rollback 時にアプリ version を downgrade しない。
