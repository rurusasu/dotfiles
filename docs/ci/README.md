# CI の実行環境と成果物

Linux の producer と consumer は GitHub-hosted Ubuntu runner 上で Nix を実行します。
macOS と Windows も native runner を使い、WSL は Windows 上の使い捨て distro で実行します。

## ツールと入力

Unix の producer・lint は共通の薄い `path:.#ci` Nix 環境から、Task、Bash、Python、Git、jq、
actionlint、statix などのツールを取得します。版はリポジトリの `flake.lock` で固定します。
アプリ本体や本番構成の依存はこの環境に含めず、producer が対象の flake output から構築します。
E2E consumer は public cache からビルド禁止で取得した Task と、artifact 内の固定済み Python / jq などを使います。
consumer は `path:.#ci` を構築しません。Bash テスト専用の Bats などは、同じ lock に従う
`path:.#runtime-tests` shell が供給します。Windows の本番導入は WinGet / PowerShell の経路で検証します。

Nix の認証と通信設定は `scripts/sh/configure-bootstrap-ci-nix.sh` が使い捨て CI ユーザーへ設定します。
GitHub token は権限600の専用設定ファイルへ保存し、ログや成果物へ含めません。
Linux の producer は Nix sandbox を有効にして構築し、native NixOS E2E は KVM を利用します。
CI の Nix daemon は store の重複排除を有効にし、producer だけ `build-gc` で空き容量連動の GC を有効にします。
同時ビルドは2件・各2 core に制限し、GC できない実行中の build directory の膨張も抑えます。
空き容量が 8 GiB 未満になると 16 GiB を目標に不要な store path を回収します。
producer の source・入力・checks・構成・rebuild tool は通常の `--out-link` で
GC root として保持し、artifact の export 前に必要な成果物を失わないようにします。
consumer の import は複数バッチを使うため自動 GC を無効にし、先行バッチの出力を回収させません。
WSL でも同じ認証設定 adapter を使い、root / nixos の両方に必要な設定を反映します。
公式 cache を優先し、Numtide と Hermes の cache も利用します。
CI は global flake registry を使わず、bootstrap の alias は明示した locked inputs から解決します。

## 全プラットフォーム共通の工程

公開入口は `task ci:build TARGET=linux|darwin|wsl|windows` と
`task ci:e2e TARGET=linux|darwin|windows` です。
工程順序は `taskfiles/ci/taskfile.yml`、OS 固有の操作は platform adapter が所有します。
job の順序は Changes → Lint → 各 Build / Plan → 対応 E2E → Complete です。
Lint は `task lint:ci` から `fmt:check` を一度実行し、statix、actionlint、
`lint:powershell`、Windows manifest の JSON 検証も終えてから各 producer を起動します。
format は sandbox 外の checkout で検査し、producer では treefmt を再実行しません。
Bash テストは Lint 後に producer と並列で、ローカルと同じ `task test:bash` を実行します。

Linux build は汎用 Nix checks、standalone Home Manager、native NixOS VM driver を構築します。
macOS build は macOS の checks と構成を、独立した WSL build は WSL の構成を構築します。
Windows plan は WinGet master と source SHA を固定します。
Windows / WSL E2E は WSL build と Windows plan のみを待ち、Linux build は待ちません。
VM driver は producer が構築し、VM 自体の実行は consumer に置きます。
事前の `nix eval` / `nix flake check --no-build` をテスト実行の代わりに重ねません。

producer は source SHA と依存を固定して artifact を保存します。
consumer は artifact の取得 → import / 本番 installer の反映 → 再起動または新しい session →
runtime 確認を実行します。consumer 内で input を更新したり、欠けた成果物を
ソースビルドで補ったりしません。PowerShell の Pester suite は E2E 後の runtime 検証を担当します。

依存更新と適用は分離します。`task update` は `flake.lock` を更新するだけで、
`install` / `nrs` / Hermes bootstrap は lock を変更せず適用します。
更新した lock は変更元の source と一緒に commit / PR に含め、producer build と E2E が
成功した SHA を適用します。適用入口と CI source archive は `--no-update-lock-file` を使い、
lock が不足・不整合なら新しい依存を選び直さず失敗します。
macOS の一時 wrapper は元 source の lock を検証後、外側の lock だけを作成します。
ローカルで source / lock を編集した場合、その変更は再検証が必要です。
保証対象は同じ source・lock・対象構成の Nix 依存で、ローカル Lifelog checkout や hardware、
版を固定していない WinGet / Homebrew の導入結果までは同一とみなしません。
コンパイルエラーは既存の package build check と構成全体の producer build が検出し、
E2E に同じコンパイル検査を重複して追加しません。

native Linux の consumer は KVM の NixOS VM で本番 `install.sh` と reboot 後の
CLI・service・health を確認します。WSL は Windows 上の使い捨て distro で
本番 setup と cold restart を確認します。macOS は別 runner で `install.sh`、
service の再起動、新しい login shell を検証します。Windows は WinGet master と
ソースの plan を受け取り、PowerShell 5.1 / 7 で本番 Winget → WSL → chezmoi と
新しい profile session を確認します。

GitHub-hosted macOS / Windows の host OS reboot は対象外です。
standalone Home Manager は build / installer contract の対象であり、
Ubuntu / Debian 上の activation E2E は含みません。
OS 分岐の契約は stub で検証し、実 OS が必要な動作は各 E2E が担当します。

push / PR は軽量な変更検出を必ず実行し、必要な job だけ起動します。
対象外の job は `if` で明示的にスキップし、検出失敗や必須 job の失敗・未完了を
集約結果の成功として扱いません。

## Nix 成果物の再利用

必須の build artifact と、任意の dependency cache は別の責務です。

- 必須 artifact は source SHA、target、root store paths、closure metadata と payload の digest を持ちます。
  consumer は producer の artifact ID を指定して取得し、入力の一致を確認します。
  公開依存は configured HTTP(S) substituter で全参照が解決する場合だけ payload を省き、
  consumer が公開依存を取得してから private NAR を import します。
  取得漏れを consumer 内のソースビルドで補わず、反映後の system が producer の root と一致することを検証します。
- `.github/actions/cache-nix` は追加 account / secret を使わず、GitHub Actions cache に任意の file binary cache を保存します。
  OS・architecture・Nix version・cache 名・flake.lock のハッシュで分離し、同じ SHA、同じ inputs、
  次に同じ実行環境の順で復元します。成功した main が共有用を保存し、PR は自身の merge ref に
  完了済み出力を保存します。PR の保存先は main や他 PR から復元できません。
  run ID と attempt をキーに含め、同じ SHA の再試行でも新しい出力を蓄積します。
  この cache が消えても必須 artifact の整合性と E2E の成功条件は変わりません。

optional cache の exporter は、設定された公開 substituter（公式、Numtide、Hermes）を調べ、
間接参照も公開された出力を保存対象から除きます。未確認の出力は private として扱います。
共有依存を優先し、private 参照がそろった出力から個別 NAR を stream 圧縮します。
大きな出力が入らなくても、収まる依存出力を保存します。公開依存を含む全 closure を一度ディスクへ
書き出してから削る方式は使いません。循環参照などで完全性を保証できない候補は保存しません。
ログには selected / skipped の件数、保存 byte 数、上限・空き容量・依存不足による見送りを出します。

保存上限は各 producer の workflow の `max-size` で指定します。
repository の cache 容量枠や課金設定を増やさず、既定の 10 GiB 枠を他 workflow と共有します。
store DB は保存せず、metadata と対応する payload がそろった file binary cache だけを保存します。
圧縮には Nix の zstd を使い、Homebrew cleanup 後も同じ compressor を使えるよう GC root と PATH で保持します。
初回や容量制限による cache eviction 時は producer が不足分を構築します。E2E consumer は構築しません。
複数 cache が repository の容量枠を共有するため、上限が各世代の永続保持を保証するわけではありません。
build step の時間上限は job 全体より短くし、失敗時も完了済み出力を保存する時間を確保します。
cache 保存には20分の上限を設けます。job 全体の timeout・キャンセル・runner 消失時の保存は保証しません。
保存・復元・artifact 転送にかかった時間と容量は hosted Actions の各工程のログで確認します。
保存ジョブの成功だけで改善完了とせず、後続実行で Linux / Darwin の両 producer に実際の cache hit があり、
不要な再ビルドを減らせていることを確認します。
