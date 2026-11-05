# Bootstrap CI tools image

`ci-nix.yml` の Linux producer は、このイメージの同じ Nix store で
通常の checks と、変更分類で選択された standalone Home Manager、WSL、native NixOS VM driver の
検査・ビルドを実行します。native Linux が選択された場合の VM runtime check は必須です。
`bash-test` もこのイメージで Bash テストを一度だけ実行します。
Nix、Bash、go-task、Git、Python 3.14、Node.js 24、statix、jq、tar、xz を事前導入します。
テスト専用ツールは checkout した flake の `runtime-tests` shell から取得します。
`nix fmt` の formatter と検証対象のパッケージは、引き続き checkout した flake から選択します。

## 更新と再利用

`ci-nix.yml` 内の `ci-tools` ジョブが Dockerfile、`nix.conf`、`check.sh`、`profile.sh` の
内容ハッシュをタグにして GHCR の既存イメージを探します。
存在しない場合だけビルド・実行検証・公開を行い、利用側へ digest を返します。
通常の dotfiles 変更や `flake.lock` 更新ではツールイメージを再ビルドしません。
ツールを更新するときは Dockerfile の base image digest / `NIXPKGS_REV` を更新します。

公開先は `ghcr.io/<owner>/<repository>/bootstrap-ci-tools` です。
公開権限はイメージ準備ジョブだけが持ち、利用側は `packages: read` で取得します。
リポジトリ内の PR、main push、手動実行は未公開の定義をビルドできます。
fork PR は公開済みイメージを読み取り専用で使用します。
fork がツール定義自体を変更した場合は、maintainer がリポジトリ内のブランチで
その定義をビルドしてから検証します。未公開定義を別のイメージに置き換えることはありません。

## 実行環境の境界

イメージは GitHub Actions の JavaScript actions に必要な共有ライブラリを持つ
Debian ベースです。公式 Nix イメージから登録済み store をコピーし、
各検査ジョブでは Nix の導入処理を実行しません。
ローカル store へ書き込む CI のため root で実行します。
Nix sandbox は有効で、Nix のビルドを行う job container は `--privileged` を指定します。
固定の Nix 設定と binary cache は `nix.conf` に置き、CI workflow では
`NIX_CONFIG` 環境変数を設定しません。GitHub token は
`scripts/sh/configure-bootstrap-ci-nix.sh` が実行ユーザーの専用設定ファイルへ
権限 600 で保存します。token をイメージに含めたり、ログへ出力したりしません。
WSL でも同じスクリプトで root / nixos の両方を設定し、builder の並列数制限を維持します。

CI の Nix ダウンロードは HTTP/1.1 を使い、無通信の待ち時間を 60 秒、取得試行を 3 回に制限します。
公式キャッシュの優先度を 10、Numtide を 50 に指定し、公式から先に公開成果物を取得します。
追加キャッシュと署名検証は維持し、必要な独自成果物は引き続き追加キャッシュから取得します。
これらは CI 専用の設定で、Linux container・macOS・WSL で共有します。
追加キャッシュの取得が途中で失敗した場合は、固定した derivation のソースビルドへ
フォールバックします。署名検証と fixed-output derivation のハッシュ検証は維持します。
Linux container の `fetchurl` は `NIX_CURL_FLAGS` でも HTTP/1.1 を指定し、接続待ちを 15 秒、
60 秒間の転送速度が 16 KiB/s 未満なら再接続します。公開前の fixed-output ビルドで、
この環境変数が実際のビルダーへ渡ることも確認します。

Nix lint は statix、format と通常の flake checks は producer の検証工程で実行します。
通常の checks はすべて保ち、native Linux の VM runtime check は OS の変更分類で選択します。
VM driver は producer で構築し、VM の実行は consumer の E2E 工程に置きます。
事前の `nix eval` / `nix flake check --no-build` をテストの代わりに重ねません。
`task ci:build TARGET=linux|darwin|windows` と `task ci:e2e TARGET=linux|darwin|windows` が共通の入口です。
工程順序は Taskfile、OS 固有の操作は platform adapter が所有します。
Linux / Darwin / Windows の producer は対象の SHA を固定して成果物を作り、
consumer は artifact の取得 → import / 本番 installer の反映 → 再起動 / 新しい session → runtime 確認を行います。

Linux producer は本番設定を取り込む VM、standalone Home Manager と WSL の共有依存を再利用します。native Linux の consumer は KVM の
NixOS VM で `install.sh` と実 reboot を確認します。WSL の consumer は Windows 上の使い捨て distro で
本番 setup と cold restart を確認します。macOS は別 runner で `install.sh`、service の再起動、
新しい login shell を検証します。Windows は WinGet master とソースの plan を受け取り、
PowerShell 5.1 / 7 で本番 Winget → WSL → chezmoi と新しい profile session を確認します。
macOS / Windows の hosted host 自体の OS reboot は対象外です。
standalone Home Manager は build / installer contract の対象で、Ubuntu / Debian の activation E2E は含みません。

Bash テストは同じ workflow の Linux `bash-test` job とローカルで `task test:bash` を実行します。
この Task は `nix develop --ignore-environment --keep HOME .#runtime-tests` で明示したツールだけを使い、
`scripts/sh/tests` を Bats に渡します。Bats の標準動作で検出と失敗・0 件の終了状態を扱います。
Darwin build job には Bash テスト用のインストール処理を置きません。
OS 分岐の契約は stub で検証し、実 OS が必要な動作は別の E2E が担当します。
push / PR では軽量な変更検出を必ず実行し、必要な job だけ起動します。

以下はホスト固有の処理を持つため、ホストで実行します。

- NixOS E2E: KVM を使う VM テストを実行する。
- Darwin / Windows / WSL E2E: 対象 OS のネイティブ環境を検証する。

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

保存上限は統合した Linux producer と Darwin producer で各 4 GiB（4,294,967,296 bytes）です。
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

## ローカル検証

リポジトリのルートから実行します。

```bash
docker buildx build --platform linux/amd64 --load \
  --tag dotfiles-bootstrap-ci-tools:local docker/bootstrap-ci-tools
docker run --rm --platform linux/amd64 --privileged \
  dotfiles-bootstrap-ci-tools:local \
  bash /usr/local/libexec/check-bootstrap-ci-tools.sh --sandbox
```

イメージのビルド時にも `check.sh` を実行します。
CI の公開前検証では、加えて sandbox 内の小さな derivation をビルドします。

Apple Silicon の Docker Desktop で amd64 をエミュレーションすると、Nix の
seccomp フィルタで失敗する場合があります。その場合のローカル検証に限り、
`docker run` に `--env 'NIX_CONFIG=filter-syscalls = false'` を追加します。
Nix sandbox は有効なままです。GitHub の amd64 runner ではこの例外を設定しません。
