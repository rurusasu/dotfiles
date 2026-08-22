# macOS Homebrew Cask Outdated Semantics Fix Design

> **Status:** Historical design. The standalone cask updater described here was superseded by nix-darwin's declarative Homebrew Bundle with `upgrade = true`.

## Goal

`nrs` の明示的な Homebrew cask 更新処理を、現在の Homebrew CLI の終了コードと tap 修飾名の扱いに適合させる。

成功条件は次のとおり。

- `brew outdated --cask --greedy <cask>` が、更新対象を stdout に出して終了コード 1 を返す場合を正常な「更新あり」と判定する。
- `stablyai/orca/orca` のような tap 修飾名でも、インストール済みの短縮 token `orca` を正しく照合する。
- 宣言された tap 修飾名は `info`、`fetch`、`upgrade` で維持し、更新元を曖昧にしない。
- 実際の検査失敗を更新対象と誤認せず、`nrs` を非ゼロで終了する。
- 修正後の `nrs` が宣言済み cask を更新し、停止済み Docker Desktop を含む後続処理まで完走する。

## Root Cause

現在の updater は、名前を指定した `brew outdated` の終了コードが 0 以外なら検査失敗としている。しかし現在の Homebrew は、指定した cask が outdated の場合に cask token を stdout へ出し、終了コード 1 を返す。この正常な outdated 状態が検査失敗として記録されるため、更新処理へ進まない。

また、nix-darwin の宣言には `stablyai/orca/orca` が含まれる一方、Homebrew のインストール済み cask registry は短縮 token `orca` を使う。updater が tap 修飾名のまま `brew list --cask --versions` を実行するため、導入済み Orca を未導入と誤判定する。

## Scope

### In scope

- updater 内で、宣言名と Homebrew の短縮 token を明確に分離する。
- 名前付き `brew outdated` の終了コード 0/1 と stdout を組み合わせて判定する。
- fake Homebrew を実際の名前付き outdated semantics に合わせる。
- 通常名、tap 修飾名、真のコマンド異常を Bats で回帰テストする。
- 修正を PR として公開し、GitHub Actions 成功後にマージする。
- ローカル `main` へ反映後、`nrs` を再実行して実 cask の収束を確認する。

### Out of scope

- cask 更新フロー全体の再設計。
- `brew outdated --json` への全面移行。
- 宣言済み cask を無条件に毎回 upgrade する方式への変更。
- tap、formula、Mac App Store アプリ、`wezterm@nightly` の管理変更。
- Homebrew 自体の終了コード仕様の変更。

## Architecture and Components

変更対象は `scripts/sh/update-homebrew-casks.sh` と、その振る舞いを検証する `tests/bash/macos_homebrew_cask_update.bats` に限定する。

updater は cask ごとに二つの識別子を持つ。

- **宣言名**: nix-darwin から取得した値。例: `stablyai/orca/orca`。`outdated`、`info`、`fetch`、`upgrade` と失敗報告に使う。
- **短縮 token**: 宣言名の最後の `/` より後。例: `orca`。インストール済み照合と `outdated` stdout の検証に使う。

短縮 token の導出は副作用のない小さな shell 関数に分離する。Homebrew への更新指示には常に宣言名を渡すため、同名 cask が複数 tap に存在しても宣言された更新元を維持できる。

`check_outdated` は Homebrew の終了コードだけで成否を決めず、stdout と短縮 token を併せて解釈する。既存のループ構造と最終収束検査は維持し、判定規則だけを一元化する。

## Data Flow

1. nix-darwin configuration から宣言名を読み込む。
2. 宣言名から短縮 token を導出する。
3. `brew list --cask --versions <短縮 token>` でインストール済みか確認する。
4. `brew outdated --cask --greedy <宣言名>` を実行する。
5. 終了コードと stdout を判定規則に従って解釈する。
6. outdated の場合だけ、宣言名で app artifact の確認、fetch、upgrade を行う。
7. 同じ識別子と判定規則で最終収束を検査する。

## Outdated 判定規則

stdout は末尾の改行を除いた完全一致で短縮 token と比較する。

- 終了コード 0、stdout が空: 最新。
- 終了コード 0、stdout が短縮 token: 更新あり。Homebrew の過去または代替実装との互換性を維持する。
- 終了コード 1、stdout が短縮 token: 更新あり。現在の名前付き Homebrew query の正常系。
- 終了コード 1、stdout が空または別の値: 判定不能として失敗。
- 終了コード 2 以上: Homebrew command の異常として失敗。

stderr は Homebrew の診断としてそのまま利用可能にし、正常な status 1 を独自の失敗ログへ変換しない。

## Error Handling

- 空の短縮 token は無効な宣言として扱い、対象 cask を失敗へ記録する。
- インストール確認に失敗した場合は、宣言名を含む既存のエラーを維持する。
- status 1 でも stdout が期待 token と一致しなければ成功扱いにしない。
- status 2 以上では status を含む検査失敗ログを出し、fetch と upgrade を実行しない。
- 最初の走査と最終収束検査の両方で同じ規則を使い、upgrade 成功後に残った outdated を見逃さない。
- updater 失敗時のアプリ再起動 trap、再試行上限、backoff、後続処理の中断は変更しない。

## Testing

fake Homebrew の `outdated` は、対象が古い場合に短縮 token を stdout へ出して status 1 で終了する。これにより、修正前の updater が失敗する回帰テストを先に作る。

Bats では次を検証する。

- 通常 cask が status 1 と一致する token で outdated と判定され、fetch と upgrade へ進む。
- 最新 cask の status 0 と空 stdout は更新されない。
- `stablyai/orca/orca` は `brew list` で `orca` を使う。
- tap 修飾名は `outdated`、`info`、`fetch`、`upgrade` で維持される。
- tap 修飾名の stdout `orca` と status 1 が正常に outdated と判定される。
- status 1 と空または不一致 stdout は検査失敗になる。
- status 65 の command failure は従来どおり失敗になり、更新処理へ進まない。
- upgrade 後の収束確認にも同じ判定規則が適用される。

検証は focused Bats、Bash 3.2 syntax check、ShellCheck、macOS 設定契約テスト、全 Bash test、pre-commit の順で行う。PR の全 GitHub Actions 成功後にのみマージする。

## Rollout and Runtime Verification

マージ後にローカル `main` を fast-forward し、外部 Terminal から `nrs` を実行する。次を確認する。

- Claude、Docker Desktop、Google Chrome、Orca、Visual Studio Code が検査失敗ではなく更新処理へ進む。
- Orca が未導入と誤判定されない。
- updater の最終収束検査に失敗が残らない。
- `install-macos.sh` の後続処理が完走し、Docker Desktop が再起動する。
- `brew outdated --cask --greedy` で、専用管理対象を除く宣言済み cask が残らない。

Orca 自身の更新によって現在の Orca セッションが終了する可能性があるため、実行は Orca 内部 terminal ではなく macOS Terminal から行う。
