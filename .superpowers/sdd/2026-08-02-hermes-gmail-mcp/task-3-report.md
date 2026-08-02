# Task 3 実装レポート: Hermes Gmail MCP の認証・接続確認

実施日: 2026-08-02

## 実装内容

- `task hermes:gmail:auth PROFILE=<profile>` と
  `task hermes:gmail:test PROFILE=<profile>` を追加した。両コマンドは Docker
  daemon、Compose ファイル、非空 profile を事前検証する。
- Bash と PowerShell の host adapter は profile 名を検証し、mounted profile home
  の実在と非 symlink を確認してから、profile 固有の
  `HERMES_HOME=/opt/data/profiles/<profile>` で実行する。`default` は `/opt/data` を
  使用する。
- `auth` は `hermes mcp login gmail` を対話実行し、正常終了後に
  `mcp-tokens/gmail.json` が regular file かつ private であることを確認する。
  `test` は同じ確認を Docker 起動前に行い、`hermes mcp test gmail` を実行する。
- OAuth client 値と token 値を引数・出力・エラーに展開しない。PowerShell は
  `-Profile` 互換 alias を維持しつつ、組み込み `$PROFILE` を上書きしない。
- Google Cloud の有効化、既存 Calendar OAuth client の再利用、315 秒 callback、
  profile 単位の認証、送信・削除をしない境界を文書化した。
- PowerShell 契約テストに、login 完了後に private token cache が存在しない場合の
  失敗を追加した。

## 検証結果

- `bats tests/bash/hermes_gmail_auth.bats`: 4/4 passed
- `pwsh -NoProfile -Command 'Invoke-Pester ...HermesGmail.Tests.ps1...'`: 4/4 passed
- `bash -n scripts/sh/hermes-gmail.sh`: passed
- PowerShell parser と PSScriptAnalyzer（Error/Warning）: passed
- `nix fmt -- --fail-on-change`: passed
- `task --list` で `hermes:gmail:auth` / `hermes:gmail:test` を確認した。
- `git diff --check`: passed

## 未実施・留意事項

- 指示どおり live OAuth、Gmail MCP 接続、Discord の実行検証は行っていない。
- PowerShell の ACL 判定は静的検査と macOS 上の Pester 契約で検証した。Windows
  filesystem 上の ACL 分岐は Windows runner または実機での追加確認が必要である。
