# Nix レイアウト

## 所有境界

| パス                      | 所有範囲                                                                       |
| ------------------------- | ------------------------------------------------------------------------------ |
| `nix/hosts/`              | system/host サービス、OS ユーザー、hardware、host 固有の NixOS/nix-darwin 設定 |
| `nix/packages/catalog/`   | カテゴリ別 package/provider metadata（各 package の単一情報源）                |
| `nix/packages/providers/` | provider 選択・正規化・coverage 検証                                           |
| `nix/packages/install/`   | installer/manifest 用 metadata                                                 |
| `nix/packages/sets.nix`   | 既存 consumer 向けの合成入口・公開 API                                         |
| `nix/home/keybindings/`   | 共通 action/key、純粋な設定生成関数、Home Manager のユーザー設定               |
| `nix/home/`               | Home Manager のユーザー環境、ユーザー systemd サービス、OS 固有設定            |
| `nix/tests/unit/`         | nix-unit による Nix 式・実効設定値のテスト                                     |
| `nix/tests/build/`        | ビルド・生成物比較・外部プロセス・VM テストの derivation                       |
| `nix/tests/fixtures/`     | テスト用の共有入力・補助 module                                                |
| `chezmoi/`                | dotfile、テンプレート、アプリ設定。Windows デスクトップ設定は Nix 生成物の配布 |

- host / hardware 設定を `nix/home/` に置かない。
- Home Manager と chezmoi で同じファイルを所有しない。

パッケージデータ、選択ロジック、配布契約、host 動作は変更理由ごとに分割します。
SSOT は「一度だけ定義する」ことであり、1 ファイルへの集約ではありません。
詳細は [分割の理由と編集先](../docs/nix/package-management.md#分割の理由と編集先) を参照してください。
キー配列は home のユーザー設定と hosts の OS 統合に分けます。Darwin は home の生成結果を
nix-darwin のサービス設定へ渡し、native NixOS は host から Home Manager module を選択します。
Windows は home の GlazeWM 設定生成関数を `nix/hosts/windows/` から呼び、生成済み成果物を
chezmoi で配布します。Windows の適用時に Nix は不要です。WSL guest と standalone Linux へ
Hyprland を自動導入しない設計です。[対応範囲・移行状況と検証](../docs/chezmoi/omarchy.md) を参照してください。

秘密情報はリポジトリや Nix モジュールに書かない。既存の 1Password / chezmoi テンプレートまたは
実行時環境変数を使い、秘密の値を Nix store に入れない。

## 設定の配置

1. 複数の構成経路で共有する OS 固有の Home Manager 設定は、core module の
   `nix/home/darwin.nix`、`linux.nix`、`wsl.nix` に追加する。standalone 専用の責務は caller が
   個別 module を組み合わせる。Darwin の standalone 用 font package と `$HOME/Library/Fonts` への
   activation は `nix/home/standalone-darwin-fonts.nix` が所有する。
2. system、host サービス、ユーザー、hardware は `nix/hosts/<host>/configuration.nix` に追加する。
   責務別に分離した host module がある場合は、その module に追加する。Darwin の system font は
   `nix/hosts/darwin/fonts.nix`、OS-wide defaults、timezone、defaults の反映 activation は
   `nix/hosts/darwin/system.nix` が所有する。host identity、サービス、Homebrew、統合固有の
   activation は `configuration.nix` に置く。各 host の `default.nix` は `configuration.nix` と
   責務別 module を import する entrypoint として維持する。Darwin の `default.nix` は配線専用とする。
3. Home Manager の OS ファイルは `imports = [ ./common.nix ];` を維持する。`common.nix` から OS 固有ファイルを import せず、共通設定内の platform-scoped な分岐は最小限に保つ。
4. パッケージ追加前に `nix/packages/catalog/` の該当カテゴリと各 OS への影響を確認する。`sets.nix` の公開 API は維持する。
5. dotfile と秘密情報は `chezmoi/` と既存の secret 経路を使い、所有を重複させない。
6. Nix 設定の変更は `nix flake check --all-systems --no-build --no-write-lock-file` で評価し、
   対象 system の `nix-unit` と関連 build check を build して検証する。
   Bats は installer、shell、外部プロセス、runtime 契約に限って実行する。
   package catalog の構造、provider metadata、Nix package 選択、source shape は
   `nix/tests/unit/package-catalog-*.nix` の nix-unit が所有し、`tests/bash/package_catalog.bats` は
   [テスト分類](tests/README.md) に記載した runtime / artifact 契約を保持する。`nixos_wsl_postinstall.bats` の `nix eval` は
   stubbed `nixos-rebuild` 境界内で選択 user と `--impure` 伝播を実 Nix eval で確認する
   runtime/integration assertion に限る。

   Repository-owned custom derivations は `checks.*.custom-package-builds` を build して確認する。
   この check は chatgpt、Dia、Neovim、Orca の supported system だけを対象にし、
   upstream nixpkgs package 全体や privileged activation は実行しない。

   テストの登録は `nix/flakes/tests.nix` が担当する。nix-unit も flake の `checks` 経由で実行する。
   `--no-build` の成功はテスト実行の成功を意味しない。[配置と実行方法](tests/README.md) を参照する。

ホストの標準レイアウトでは `nix/hosts/<host>/default.nix` と
`nix/hosts/<host>/configuration.nix` を必須の基本構成とし、必要に応じて `default.nix` が
責務別 module を import します。Darwin、native NixOS、NixOS-WSL はいずれもこの構成を使い、
Darwin では `fonts.nix` と `system.nix` を分離しています。

## Codex CLI

Codex CLI の全 OS npm 統一方針と、別製品であるデスクトップ AppX の責務分担は
[`docs/nix/codex-cli.md`](../docs/nix/codex-cli.md) を参照する。
