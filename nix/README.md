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
2. system、host サービス、ユーザー、hardware は `nix/hosts/<host>/configuration.nix` に追加する。
   各 host の `default.nix` は `configuration.nix` を import する entrypoint として維持する。
3. Home Manager の OS ファイルは `imports = [ ./common.nix ];` を維持する。`common.nix` から OS 固有ファイルを import せず、共通設定内の platform-scoped な分岐は最小限に保つ。
4. パッケージ追加前に `nix/packages/sets.nix` の所有範囲と各 OS への影響を確認する。
5. dotfile と秘密情報は `chezmoi/` と既存の secret 経路を使い、所有を重複させない。
6. Nix 設定の変更は `nix flake check --all-systems --no-write-lock-file` と focused `nix-unit`
   build で検証する。Bats は installer、shell、外部プロセス、runtime 契約に限って実行する。
   既存の `tests/bash/package_catalog.bats` だけは、`nix/tests/home/README.md` に完全分類した
   一時的な catalog/Nix/source-shape 例外であり、`nixos_wsl_postinstall.bats` の `nix eval` は
   stubbed `nixos-rebuild` 境界内で選択 user と `--impure` 伝播を実 Nix eval で確認する
   runtime/integration assertion に限る。新しい例外は追加しない。

ホストの標準レイアウトは `nix/hosts/<host>/default.nix` と
`nix/hosts/<host>/configuration.nix` の組み合わせです。Darwin、native NixOS、NixOS-WSL
はいずれもこの構成を使います。

## Codex CLI

Codex の Nix 更新方針と Windows の winget との責務分担は
[`docs/nix/codex-cli.md`](../docs/nix/codex-cli.md) を参照する。
