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

## Fix round 1: OAuth キャッシュ親と ACL の防御

### 修正内容

- Unix / PowerShell adapter は OAuth login 前に profile 内の `mcp-tokens` を作成して
  検証し、symlink・非ディレクトリ・profile home 外へ解決される親を拒否する。
  OAuth login 後も親と `gmail.json` の profile home 内包含を再検証するため、認証中の
  symlink 置換で token を profile 外へ保存した状態を成功扱いにしない。
- Windows の token cache ACL は、file owner、`SYSTEM` (`S-1-5-18`)、
  `Administrators` (`S-1-5-32-544`) だけを read-capable Allow ACE の許可対象とする。
  `Authenticated Users` を含むほかの identity の `ReadData` Allow ACE は拒否する。
- OAuth consent の正確な scope を
  `https://www.googleapis.com/auth/gmail.readonly` と
  `https://www.googleapis.com/auth/gmail.compose` として文書化した。
- Bash と PowerShell の両方に、login 前と login 後の parent-symlink 置換を検証する
  契約を追加した。PowerShell には、Windows で `Authenticated Users` の ReadData を
  付与して拒否を確認する契約も追加した（非 Windows ではこの ACL 契約のみ skip）。

### 検証結果

- `bats tests/bash/hermes_gmail_auth.bats`: 6/6 passed
- `pwsh -NoProfile -Command 'Invoke-Pester -Path scripts/powershell/tests/HermesGmail.Tests.ps1 -Output Detailed'`: 6 passed, 0 failed, 1 skipped / 7 total
- 必須 runner:
  `pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/HermesGmail.Tests.ps1 -MinimumCoverage 0`
  は `6 passed, 0 failed, 1 skipped / 7 total` で exit 0。
- Bash syntax、PowerShell parser、PSScriptAnalyzer（Error/Warning）、
  `nix fmt -- --fail-on-change`、`git diff --check` を実行した。

### 未実施・留意事項

- Task 4 の live OAuth、Gmail MCP、Discord 検証は実行していない。
- `Authenticated Users` ACL 契約は Windows 専用であり、この macOS 実行では skip。

## Fix round 2: OAuth login 中の mcp-tokens bind mount 固定

### 修正内容

- re-review で確認された race は、login 前後の host path 検査だけでは閉じられず、
  Hermes が主 `/opt/data` bind mount 経由で host の `mcp-tokens` を再解決できる点
  だった。
- Unix と PowerShell の `auth` / `test` で、検証済みの canonical host
  `mcp-tokens` directory を source とする dedicated read-write mount を追加した。
  target は named profile では
  `/opt/data/profiles/<profile>/mcp-tokens`、default では
  `/opt/data/mcp-tokens` となる。既存の profile、symlink、cache privacy の検証と
  login 後の再検証は維持している。
- 契約テストで auth と test の `--volume <source>:<target>:rw` bind mount を確認し、
  source が profile home の `mcp-tokens`、target が同じ profile の container path
  であることを固定した。

### 検証結果

- `bats tests/bash/hermes_gmail_auth.bats`: 6/6 passed
- `pwsh -NoProfile -Command 'Invoke-Pester -Path scripts/powershell/tests/HermesGmail.Tests.ps1 -Output Detailed'`: 6 passed, 0 failed, 1 skipped / 7 total
- 必須 runner:
  `pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/HermesGmail.Tests.ps1 -MinimumCoverage 0`
  は `6 passed, 0 failed, 1 skipped / 7 total` で exit 0。
- Bash syntax、PowerShell parser、PSScriptAnalyzer（Error/Warning）、
  `nix fmt -- --fail-on-change`、`git diff --check` を最終実行した。

### 未実施・留意事項

- Task 4 の live OAuth、Gmail MCP、Discord 検証は引き続き実行していない。
- dedicated bind mount は Docker が mount source を解決した後の login 中の path
  置換を防ぐ。Docker daemon 起動前の host path race はこのホスト adapter の検査と
  Docker の mount 作成境界に依存するため、実 Docker を用いた live OAuth は未検証。
