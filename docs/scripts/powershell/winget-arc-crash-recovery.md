# Arc の WinGet クラッシュ回復

## 方針と検証条件

WinGet source の `TheBrowserCompany.Arc` 導入が `-1073740791`
(`C0000409`) で異常終了した場合だけ、同じ引数で新しいプロセスを最大 1 回起動する。
元の導入タイムアウトの残り時間を使い、残りが 1 秒未満なら再起動しない。
初回出力は診断に残すが、no-op 判定には最終試行の出力だけを渡す。
回復試行の非ゼロ終了は既存導入状態によって成功へ変換しない。
終了コード 0 の後にも従来の Arc AppX manifest / executable 検証が必要。
依存、hash 検証、source 指定、GUI E2E と集約ゲートは変更しない。

## Adversarial review record

- Reviewer: `01a1252c-2ddc-7c52-be72-4dcbf6028841`
- Date: 2026-10-10
- Decision: 限定的な回復策として検証段階へ採用。
- Residual risk: 再試行が実環境で有効かは新 head の GUI E2E で確認する。
- Unresolved uncertainty: WinGet 内部のクラッシュ箇所と原因は未確定。

### Hypothesis

新しい WinGet プロセスなら依存導入後の状態で Arc 導入を続行できる可能性がある。
異常終了コードだけでは一過性障害や依存登録完了を証明しない。
同じクラッシュの再発、別エラー、タイムアウト、最終 Arc 検証失敗は回復成功を反証する。

### Empirical validation

PR #710 head `a64cda7de1a43c9dc661c819a3fad65f75c49e6b` の
[PS5.1 job](https://github.com/rurusasu/dotfiles/actions/runs/38038240603/job/114173123158) と
[PS7 job](https://github.com/rurusasu/dotfiles/actions/runs/38038240603/job/114173123193) はともに失敗。
WinGet 1.11.510、Windows Server 10.0.26100.33438、Arc 1.125.0.458。
Windows App Runtime 1.5.9 の成功表示直後に異常終了し、Arc 本体の導入成功証拠はない。
アップロードされた WinGet 診断ログは依存 installer の削除処理で終わる。
この最終行はクラッシュ箇所を確定しない。ローカル PC へ実ソフトは導入しない。
回帰テストは外部 WinGet 境界だけを mock して実ハンドラーの試行回数、結果、検証を確認する。
本番変更前に回復固有のテスト失敗を確認した。ローカル単体テストだけでは E2E 復旧を証明しない。

### Alternative comparison

- 現状維持: 最小リスクだが導入は失敗したまま。
- 限定再試行: source / installer / 依存管理を維持し、追加実行は 1 回・元の時間予算内。
- CI の WinGet 更新: 有力な比較案だが、この障害への有効性は未検証。版固定と別途検証が必要。
- 依存の先行導入: 登録状態を比較できるが SSOT 外の依存管理と実行経路が増える。
- Arc / 依存 / 検証の skip: 機能と検証を弱めるため不採用。

### Published prior art

2026-10-10 に `microsoft/winget-cli` の issues / PR / v1.11.510 source を
`C0000409`, `Arc`, `WindowsAppRuntime crash`, `Removing installer` で調査。
[PR #5807](https://github.com/microsoft/winget-cli/pull/5807) は 1.11.510 の
CI クラッシュ疑いにイベントログ収集を追加するが、今回の原因や再試行有効性を保証しない。
[InstallFlow.cpp](https://github.com/microsoft/winget-cli/blob/v1.11.510/src/AppInstallerCLICore/Workflows/InstallFlow.cpp)
では依存導入後に後処理を経て親パッケージ処理へ戻る。
[PR #6496](https://github.com/microsoft/winget-cli/pull/6496) の同じ終了コードは
SYSTEM / COM activation の別条件であり、今回へ同一原因として転用しない。
この調査範囲で完全一致の原因・回復保証は見つからない。
新しい配布元、依存ライブラリ、ライセンス対象のコードは導入しない。

### Reviewer verification

独立した read-only reviewer がログ、上流 source、代替案と境界条件を調査。
依存完了の未証明、終了コードの非一意性、no-op / 既存導入の誤成功、時間予算を指摘した。
言語依存の成功文言ゲートは採用せず、正確な package / source / native code に限定する。
最終出力のみの判定、失敗保持と残り時間の回帰テストへ反映した。
実 GUI E2E が成功するまでは復旧済みと扱わない。
