# Nix レイアウト

## 所有境界

| パス                    | 所有範囲                                                                       |
| ----------------------- | ------------------------------------------------------------------------------ |
| `nix/hosts/`            | system/host サービス、OS ユーザー、hardware、host 固有の NixOS/nix-darwin 設定 |
| `nix/packages/sets.nix` | クロスプラットフォームのパッケージ集合（単一情報源）                           |
| `nix/home/`             | Home Manager のユーザー環境、ユーザー systemd サービス、OS 固有設定            |
| `chezmoi/`              | Nix で表現しない dotfile、テンプレート、アプリ設定                             |

- host / hardware 設定を `nix/home/` に置かない。
- Home Manager と chezmoi で同じファイルを所有しない。

秘密情報はリポジトリや Nix モジュールに書かない。既存の 1Password / chezmoi テンプレートまたは
実行時環境変数を使い、秘密の値を Nix store に入れない。

## 設定の配置

1. OS 固有の Home Manager 設定は対象 OS の `nix/home/darwin.nix`、`linux.nix`、`wsl.nix` に追加する。
2. system、host サービス、ユーザー、hardware は `nix/hosts/` に追加する。
3. Home Manager の OS ファイルは `imports = [ ./common.nix ];` を維持する。`common.nix` から OS 固有ファイルを import せず、共通設定内の platform-scoped な分岐は最小限に保つ。
4. パッケージ追加前に `nix/packages/sets.nix` の所有範囲と各 OS への影響を確認する。
5. dotfile と秘密情報は `chezmoi/` と既存の secret 経路を使い、所有を重複させない。
6. 対象 OS の評価・テストと `tests/bash/home_layout.bats` を実行する。

## Codex CLI

Codex の Nix 更新方針と Windows の winget との責務分担は
[`docs/nix/codex-cli.md`](../docs/nix/codex-cli.md) を参照する。
