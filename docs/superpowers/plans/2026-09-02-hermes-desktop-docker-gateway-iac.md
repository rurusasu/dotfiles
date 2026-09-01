# Hermes Desktop Docker gateway 接続 IaC 実装計画

> **実行方針:** この計画は専用 worktree `fix/hermes-desktop-docker-gateway-iac` で、各ステップをテスト先行で実行する。

## 1. 既存状態と設計の固定

- [ ] Issue #545、`docs/hermes-agent/desktop.md`、Docker Compose のポート、Hermes runtime env の責務を照合する。
- [ ] 設計文書に、9119 を Remote Gateway、8642 を health 用 API とする区別、secret 境界、app-owned state 非管理を記録する。
- [ ] ベースラインの Bats/Python テストを実行し、変更前の結果を保存する。

## 2. ランチャーの失敗テストを追加

- [ ] `tests/bash/hermes_desktop.bats` を追加し、fixture の HOME/HERMES_DATA_DIR と fake `hermes-desktop`/`curl` を用意する。
- [ ] 正常系で `HERMES_DESKTOP_REMOTE_URL` が `http://127.0.0.1:9119`、token が fake Desktop の環境変数へ渡ることを検証する。
- [ ] token が引数・出力へ出ず、欠損、重複、形式不正、symlink、0600 以外の env を拒否するテストを書く。
- [ ] gateway 不到達時に Desktop を実行せず、`task hermes:up` を案内するテストを書く。
- [ ] 先にテストを実行して失敗することを確認する。

## 3. Nix catalog と launcher を実装

- [ ] `scripts/sh/hermes-desktop-docker.sh` に strict mode、env parser、secret 検証、health check、`exec` を実装する。
- [ ] `nix/packages/sets.nix` に Darwin/WithHermes 専用の `hermes-desktop-docker` package を追加し、非 Darwin は reviewed unsupported とする。
- [ ] runtime dependency は Nix wrapper の `curl`/`gawk` へ閉じ込め、token を derivation 内容へ埋め込まない。
- [ ] テストを再実行して正常系・拒否系を green にする。

## 4. Taskfile とドキュメントを更新

- [ ] `taskfiles/hermes/taskfile.yml` に Darwin 限定の `hermes:desktop` 起動タスクを追加し、wrapper を canonical entrypoint とする。
- [ ] `docs/hermes-agent/desktop.md` に `hermes-desktop-docker`、`task hermes:up`、secret 境界、9119/8642 の診断方法を記載する。
- [ ] Taskfile/catalog 契約テストを追加・更新する。

## 5. 検証と引き渡し

- [ ] 関連 Bats、Python 契約テスト、Nix formatter/eval、Taskfile config を実行する。
- [ ] 実機で secret を表示せず、9119 gateway health と wrapper の fake/live 起動境界を確認する。
- [ ] `git diff --check`、最終差分、git status、Issue #545 の受け入れ条件をレビューする。
- [ ] `task commit -- "feat: connect Hermes Desktop to Docker gateway"` で専用ブランチへコミットする。
