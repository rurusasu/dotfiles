# Codex CLI の全 OS 更新経路統一

## 目的

`nrs` を実行したときに、Codex CLI を含む依存パッケージが各 OS の最新定義へ追従するようにする。現在の macOS 経路は `nix-darwin switch` のみを実行し、`flake.lock` を更新しないため、ロック済みの古い `nixpkgs` に含まれる Codex が継続して使われる。

## 対象範囲

- macOS: `install.sh` から呼ばれる `install-macos.sh`
- NixOS: `install.sh` から呼ばれる `install-nixos.sh`
- Debian/Ubuntu: `install.sh` から呼ばれる `install-linux.sh`
- Linux のユーザー専用 Home Manager 経路: `install-home-manager.sh`
- Windows: `install.cmd` / PowerShell の Phase 1 Winget 経路

Windows は Nix の `flake.lock` を使わないため、`OpenAI.Codex` を含む Winget パッケージの更新経路を明示的に保証する。

## 設計

### Unix 系の共通更新処理

`scripts/sh/update-flake.sh` を追加し、次を一元化する。

1. `nix` が利用可能であることを確認する。
2. リポジトリのルートで `nix flake update` を実行する。
3. 失敗した場合は `dotfiles_die` 相当のエラーで終了し、後続の再構築・Home Manager 適用を行わない。

各 Unix インストーラーは、Nix の準備と checkout のリンク確立後、システムまたは Home Manager の build/apply より前に共通処理を呼ぶ。これにより `flake.lock` 更新が成功した状態だけを後続処理へ渡す。

既存の prebuilt NixOS E2E 経路でも更新処理の契約は維持するが、テストでは Nix コマンドをスタブ化する。更新処理の失敗時に `nixos-rebuild`、`darwin-rebuild`、System Manager、Home Manager が呼ばれないことを回帰テストで確認する。

### Windows の Codex 更新処理

Winget の通常 import はインストール済みパッケージにも latest を選ばせる既存契約を持つが、Codex の更新要求を明確にするため、Winget ハンドラーに更新対象の明示的な処理を追加する。

- `OpenAI.Codex` がパッケージ定義に存在する場合、`winget upgrade --id OpenAI.Codex --exact --silent --accept-package-agreements --accept-source-agreements` を実行する。
- 更新対象が未インストールの場合は既存の install 処理に委ねる。
- upgrade が「更新なし」を返すケースは成功として扱う。
- 実際の更新失敗は Phase 1 の失敗として返し、後続 Phase へ進ませない。
- 既存の portable shim 更新、Codex の `verifyCommand`、他パッケージの install/verify 動作は維持する。

Windows の処理は `OpenAI.Codex` に限定し、全 Winget パッケージを無条件に upgrade する変更は行わない。これにより、既存のインストール契約とユーザーが明示した Codex 更新要求を分離する。

## エラー処理

- Unix: `nix flake update` の非ゼロ終了を即時エラーとし、再構築を実行しない。
- Windows: Codex の明示的 upgrade が、更新なし以外の失敗を返した場合は Phase 1 を失敗させる。
- ロックファイルや生成済み Windows パッケージ一覧は、実行結果として Git 差分に現れる。自動 commit や push は行わない。

## テスト方針

- Bash の各 Unix インストーラーテストで、更新コマンドが build/apply より先に呼ばれることを確認する。
- Bash で更新コマンドが失敗した場合、後続の build/apply が呼ばれないことを確認する。
- PowerShell の Winget ハンドラーテストで、インストール済み Codex に対する明示的 upgrade、未インストール Codex の install フォールバック、更新なしの成功、更新失敗の Phase 1 失敗を確認する。
- 既存の Bash / PowerShell テスト、Nix formatter、PowerShell analyzer を実行する。

## 非対象

- Codex CLI のバージョンをリポジトリ内で固定すること
- Codex の配布元を変更すること
- Homebrew cask の更新方式を変更すること
- Windows の全パッケージを無条件に upgrade すること
- 更新後の自動 commit、push、PR 作成
