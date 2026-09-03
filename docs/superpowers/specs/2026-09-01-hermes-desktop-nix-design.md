# Hermes Desktop Nix 管理設計

> **廃止済み:** 2026-09-03 に [#554](https://github.com/rurusasu/dotfiles/issues/554)
> で Homebrew Cask 管理へ移行しました。現行構成は
> [Hermes Desktop の運用](../../hermes-agent/desktop.md) を参照してください。

## 目的

`--with-hermes` を選んだ macOS 環境で、Hermes Desktop をホスト側の Nix
管理下に置き、Hermes Agent の実行環境と Web Dashboard は既存の Docker
Compose に残す。Desktop は GUI クライアントとしてコンテナの Dashboard に
接続できる構成にする。

## 決定事項

- Hermes Desktop は公式 `NousResearch/hermes-agent` flake の
  `packages.<system>.desktop` を root flake input に追加して固定する。
- `nix/packages/sets.nix` をパッケージカタログの SSOT とし、カタログ ID
  `hermes-desktop` に `installFeature = "WithHermes"` を設定する。
- `--with-hermes` が有効な macOS では、Home Manager のユーザーパッケージ
  として Desktop を反映する。通常プロファイルでは評価・インストールしない。
- Desktop を `hermes-agent` コンテナへ入れない。コンテナは gateway、API、
  Web Dashboard、既存の MCP/Browser サービスを担当する。
- Desktop のリモート接続先は `http://127.0.0.1:9119` とし、資格情報や
  Hermes のランタイム状態は Nix 式・Nix store に置かない。
- `x86_64-darwin` は現在の公式 Desktop 出力が対象外のため、既存の flake
  system matrix どおり Apple Silicon を対象とする。

## 受け入れ条件

1. `nix flake check --no-build --impure --all-systems` の既存 bootstrap VM
   評価エラーを除き、今回の変更由来の評価エラーがない。
2. `hermes-desktop` が `WithHermes` でのみ Darwin system package に解決され、
   通常プロファイルには現れない。
3. 公式 flake input の lock 情報と Desktop 出力を Nix が評価できる。
4. 既存の macOS installer の `--with-hermes` 契約、Compose 契約、パッケージ
   カタログ検証、ドキュメントが更新される。
5. Hosted Actions が成功し、PR のレビューコメントが解決済みである。
