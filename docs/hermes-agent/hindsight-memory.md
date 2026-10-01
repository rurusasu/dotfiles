# Hermes Hindsight ローカルメモリ運用

## Architecture

Hindsight は Hermes から独立したホスト共通の永続メモリサービスです。Compose の
`hindsight` サービスが埋め込み PostgreSQL、ローカル reranker、メモリ API を提供し、
`local-ai-services` ネットワークを所有します。native Hermes は loopback の
`http://127.0.0.1:8888` を使います。推論・埋め込みは MLflow Gateway の論理 endpoint
`ollama-chat-default` と `ollama-embedding-default` を `local-ai-services` 経由で使い、
MLflow だけが設定済み provider として native host Ollama に接続します。

Hermes Agent は Nix flake の Home Manager module で管理し、Hindsight の
profile 設定は native bootstrap が同期します。Docker は Hindsight/MLflow の
独立 sidecar にだけ使用し、Hermes gateway backend には使用しません。

Hindsight のイメージは
`ghcr.io/vectorize-io/hindsight:0.9.1@sha256:a0e937366261b8a8f20ebcaf13758c689c381dcbbf01684e4375c2787c8c666d`
に固定されています。API と UI はホストの loopback にのみ公開され、内蔵
PostgreSQL にホスト公開ポートはありません。Hindsight は Hermes Compose の
`depends_on` や停止 lifecycle には含めません。ただし `hermes:setup` と
`hermes:bootstrap` は `hindsight:up` を先に実行し、external network と memory
service が存在する状態を保証します。Hindsight が停止すると recall/retain は使え
ませんが、Hermes gateway を停止・再起動させる構成ではありません。

## Supported platforms

通常の dotfiles 経路で Windows、macOS、Ubuntu/Debian、NixOS を対象にします。
Ollama は各ホストで一つだけ動かします。macOS は Homebrew cask、Windows は
winget、Ubuntu/Debian は System Manager、NixOS は NixOS サービスが提供します。

Linux の native Ollama は Docker bridge の `host-gateway` から到達できるように
します。NixOS は `0.0.0.0:11434` でlistenしますが、firewallでは`11434`を開放
しません。Ubuntu/Debian の System Manager は `docker0` のgateway addressだけに
bindし、外部interfaceへOllama APIを公開しません。macOSとWindowsのbind設定は
変更しません。Composeの`hermes`と`hindsight`は、どちらもLinuxで
`host.docker.internal`を解決できるよう`host-gateway`を設定します。

WSL では Ollama を Linux 側へ追加・常駐させません。Windows 側で Ollama を
インストールして実行し、Docker の `host.docker.internal` 別名から Windows
ホストの `11434` へ到達させます。WSL の Ollama サービスを有効化して二重起動
してはいけません。

ここで説明する host gateway と `11434` への到達経路は、準備処理と受入検証が
native Ollama のモデル存在・readiness を確認するためだけのものです。Hindsight の
推論リクエストは常に MLflow Gateway を経由し、`host.docker.internal:11434` に
推論を直接送信しません。`/api/tags` と `/api/version` はそれぞれ model inventory
と readiness probe に限られ、inference request を運びません。

## Installation

Windows のインストーラーはサービス単位のスイッチを受け付けます。`-WithDocker` は
Docker のみ、`-WithMLflow` は Ollama と Docker に加えて MLflow、`-WithHindsight` は
さらに Hindsight を有効にします。`-WithHermes` は NixOS WSL の native Hermes と
そのデスクトップ依存を選択しますが、Hindsight/MLflow/Ollama/Docker sidecar は有効に
しません。Hermes と Hindsight memory を併用する場合は `-WithHermes -WithHindsight`
のように明示します。引数なしでは optional service を変更しません。
Hindsight 単体の通常の操作入口は次です。

```text
task hindsight:up
```

この処理は MLflow を先に起動・設定し、native host Ollama へモデルを取得し、
`${HINDSIGHT_DATA_DIR:-~/.local/share/hindsight}/pg0` と `cache` を作成してから
Hindsight だけを起動します。Hermes の起動・停止は行いません。

旧 Hermes Compose の `hermes-hindsight` と
`${HERMES_DATA_DIR:-~/.hermes}/hindsight` を使う構成のサポートは終了しています。
通常の起動は現行 `HINDSIGHT_DATA_DIR` だけを使用します。旧保存先のコピー、
`.legacy-migration-source` marker の作成・参照、旧 container の停止・削除・
障害時復旧は行いません。以前の marker が残っていても起動には影響せず、
旧データや marker を自動削除しません。起動や API/DB readiness の確認が失敗した場合は
現行 Hindsight の停止を試み、失敗を返します。現行データの退避・移動は行いません。

## Manual migration from the retired Hermes service

旧保存先にだけ記憶がある端末では、通常起動の前に管理者が手動移行します。
現行データがすでにある場合は上書き・併合せず、使用する database を選び、
両方を別々に backup してください。稼働中の database のファイルはコピーしません。

1. 旧 container の mount から実際の保存先を確認します。
   `docker container inspect hermes-hindsight --format '{{json .Mounts}}'` と
   `HERMES_DATA_DIR`、`HINDSIGHT_DATA_DIR` の設定を照合し、両方が同じ保存先を
   指していないことを確認します。旧 container が存在しない場合も旧保存先を確認します。
2. 旧 container が稼働していれば `docker stop hermes-hindsight` を実行し、
   現行側は `task hindsight:down` で停止します。ほかに同じ database を使う
   container がないことを確認し、両方の writer が停止してから次へ進みます。
3. このページの Backup / Restore と同じ境界で、旧保存先の `pg0` と `cache` だけを
   所有者・アクセス制御を維持して backup します。復元先は空の現行保存先にし、
   Bash では `cp -a`、Windows では所有者・ACL を保持できる backup/restore ツールで
   この二つだけをコピーします。profile 設定や acceptance の state/evidence はコピー
   しません。旧原本は残し、marker の新規作成は不要です。
4. database を作成した Hindsight version と現行の固定 image の互換性を確認してから
   `task hindsight:up` を実行します。`task hindsight:verify` で API/DB health を確認し、
   既存 bank の記憶を読み取り確認します。必要に応じて
   `task hermes:memory:verify` で persistence を含む受入検証も実行します。
5. 確認後、停止済みの旧 container を `docker rm hermes-hindsight` で退役します。
   `-v` や volume prune は使わず、旧原本と backup を保存します。移行失敗時は
   現行サービスを停止して writer がないことを確認し、保存した backup と旧原本から
   手動で復元・診断します。通常起動が旧サービスを再開することはありません。

## Model inventory

モデルと Hindsight の非秘密ランタイム設定のソースは
`docker/hindsight/hindsight.env` です。現在のモデルは次のとおりです。

| 用途     | 値                                        |
| -------- | ----------------------------------------- |
| LLM      | `qwen3.6:35b`                             |
| 埋め込み | `qwen3-embedding:0.6b`                    |
| reranker | `BAAI/bge-reranker-v2-m3`（ローカル CPU） |

ホスト準備は `qwen3.6:35b` と `qwen3-embedding:0.6b` を native Ollama から取得します。
Hindsight の chat 推論は `local-ai-services` 上の MLflow Gateway
`http://mlflow:5000/gateway/mlflow/v1` を使い、embedding 推論は
`http://mlflow:5000/gateway/openai/v1` を使います。モデル値にはそれぞれ
`ollama-chat-default` と `ollama-embedding-default` を指定します。モデル取得、
`/api/tags`、`/api/version` readiness probe は native Ollama の直接 model-management
操作であり、MLflow trace にはなりません。

## Startup

通常の起動入口は次です。

```text
task hindsight:up
```

Hermes 本体は `task hermes:up` で起動します。Hindsight は別サービスとして
`task hindsight:up` で管理し、managed profile の設定は `task hermes:sync` で同期します。

起動の成否はポートの listen だけで判断せず、`/health` の `status` が
`healthy` かつ `database` が `connected` であることを確認します。

推論経路を確認する場合は、先に `task mlflow:verify` を実行します。この検証は
chat と embeddings を Gateway 経由で送信し、両方の論理 endpoint ID が MLflow の
trace search 結果に現れることを要求します。コンテナの health、native Ollama の
直接応答、または trace のない Gateway 応答だけでは Hindsight 移行の証拠になりません。

## Status

サービス状態と API ヘルスは次で確認します。

```text
task hindsight:status
curl --fail --silent --show-error http://127.0.0.1:8888/health
```

既定の公開先は次のとおりです。環境変数でポートを変更している場合は、その値を
使います。

| 対象                                           | 既定の URL               |
| ---------------------------------------------- | ------------------------ |
| Ollama API（準備/受入の model/readiness 専用） | `http://127.0.0.1:11434` |
| Hindsight API                                  | `http://127.0.0.1:8888`  |
| Hindsight UI                                   | `http://127.0.0.1:9999`  |

Status の Ollama URL は model pull、`/api/tags`、`/api/version` の確認用です。
Hindsight inference はこの URL を使わず、chat では
`http://mlflow:5000/gateway/mlflow/v1`、embedding では
`http://mlflow:5000/gateway/openai/v1` と論理 endpoint 名を使います。

## Logs

Hindsight の直近ログを追跡するには次を使います。

```text
task hindsight:logs
```

Hermes native gateway 側の状態は `task hermes:profile:status PROFILE=rick` などで
確認します。
ログや API 応答に会話内容が含まれ得るため、共有時は内容を確認してください。

## Profile bank mapping

Codex の公式 Hindsight hook はホストと Tart の両方で
`http://127.0.0.1:8888`、bank `codex-shared` を使用します。Tart 起動中は SSH
reverse forward が同じ loopback endpoint をホストへ転送するため、両方の Codex
セッションが同じ記憶を retain/recall します。Ollama 自体には会話メモリを持たせず、
Hindsight の推論・埋め込み backend としてのみ利用します。

bootstrap は root/default と manifest にある全 named profile の
`hindsight/config.json` をトランザクションで管理します。設定ファイルは各
`$HERMES_HOME/hindsight/config.json` にあり、モードは `0600`、その
`hindsight` ディレクトリは `0700` です。`bank_id_template` は
`hermes-{profile}` です。

| Hermes profile | 設定パス                                                | Hindsight bank     |
| -------------- | ------------------------------------------------------- | ------------------ |
| `default`      | `$HERMES_HOME/hindsight/config.json`                    | `hermes-default`   |
| `rick`         | `$HERMES_HOME/profiles/rick/hindsight/config.json`      | `hermes-rick`      |
| `hoffman`      | `$HERMES_HOME/profiles/hoffman/hindsight/config.json`   | `hermes-hoffman`   |
| `risarisa`     | `$HERMES_HOME/profiles/risarisa/hindsight/config.json`  | `hermes-risarisa`  |
| `nancy`        | `$HERMES_HOME/profiles/nancy/hindsight/config.json`     | `hermes-nancy`     |
| `kuroda`       | `$HERMES_HOME/profiles/kuroda/hindsight/config.json`    | `hermes-kuroda`    |
| `shiraishi`    | `$HERMES_HOME/profiles/shiraishi/hindsight/config.json` | `hermes-shiraishi` |

データベースは `${HINDSIGHT_DATA_DIR:-~/.local/share/hindsight}/pg0`、reranker cache は
同じルートの `cache` にあります。これらのメモリデータは
profile Git repository には含まれません。

## Acceptance evidence

完全なライブ受入検証は次の一つの入口で実行します。

```text
task hermes:memory:verify
```

この検証は skip なしで Compose 構成確認、ホスト/モデル準備、Hindsight の
ヘルス確認、20 件の strict probe、全 7 profile の bank 分離、Hindsight 再起動後の
永続性確認、degraded mode、復旧、テスト用 bank の cleanup を順に実行します。
成功時の evidence は `${HERMES_HOME}/hindsight/acceptance.json`、実行中の state は
`${HERMES_HOME}/hindsight/acceptance-state.json` です。失敗時は診断のため failed-run
bank と state を保存し、cleanup しません。保存済み state がある間は新しい seedを
開始せず、前回runのbank IDを上書きしません。verify完了時のevidenceは`verified`
であり、degraded mode完了時に`degraded`、Hermes healthとHindsight復旧確認後に
`recovered`へ進み、全bank cleanupが成功した後にだけ`passed`になります。
Hindsight停止後に検証が失敗した場合も再起動を試みます。retain/recallの各operationと
own-sentinel recall全体は300秒未満でなければ失敗します。

## Backup

バックアップ前に Hindsight だけを停止します。

```text
task hindsight:down
```

停止を確認してから、`${HINDSIGHT_DATA_DIR:-~/.local/share/hindsight}/pg0` と
同じルートの `cache` の二つのディレクトリだけを archive します。
`config.json`、受入検証の state/evidence、profile ディレクトリ、または
`${HERMES_DATA_DIR}` 全体を memory database backup として混在させません。

メモリデータには私的な会話本文が含まれ得ます。archive は元の所有者とアクセス
制御を維持できる、暗号化された保管先へ置いてください。

## Restore

復元中は Hindsight を停止したままにします。復元先を空の
`${HINDSIGHT_DATA_DIR:-~/.local/share/hindsight}` ディレクトリにし、backup に含めた `pg0` と
`cache` だけを元の所有者で戻します。既存データへ上書き・併合はしません。

復元後に Hindsight を起動し、必ず persistence phase を含む次の検証を実行します。

```text
task hermes:memory:verify
```

検証に失敗した場合は cleanup を強行せず、失敗した bank と evidence を診断に残します。

## Upgrade

Hindsight の version upgrade は `latest` を使う通常運用ではありません。Compose の
固定 tag と digest を意図して変更する gated change として扱います。順序は次のとおり
です。

1. 現行 database の `pg0` と `cache` を前節の手順で backup する。
2. 固定 tag と digest を変更し、Compose contract test を実行する。
3. bootstrap、host adapter、acceptance の全 deterministic suite を実行する。
4. 新しいイメージを起動し、`task hermes:memory:verify` による full live acceptance を実行する。

Compose contract test は次です。

```text
task hermes:bootstrap:test
```

database migration が必要な version では、backup を migration 前の必須 gate とします。
検証を通過するまで旧 archive を削除せず、`latest` や未固定 digest に置き換えません。

## Degraded mode

Hindsight を意図的に停止しても Hermes gateway は稼働を続ける必要があります。完全な
検証は Hindsight 停止時に memory prefetch が注入しないこと、非同期 turn sync が
例外で gateway を止めないこと、明示 retain/recall が成功扱いにならないこと、さらに
Hermes の one-shot 応答と `/health` を確認します。

障害時は Hindsight のヘルスとログを確認して復旧します。Hindsight 側の停止を理由に
Hermes を Hindsight の起動依存へ変更してはいけません。

## Privacy boundary

この provider は raw user text と final-assistant text をローカル Hindsight service へ
送ります。retain mission は credential、token、private key、authentication material を
抽出しないための指針ですが、redaction を保証しません。貼り付けた credential や
private key がローカル retained document に残る可能性があります。

Hermes chat には credential、token、private key、その他の認証情報を貼り付けないで
ください。local-only 通信であっても、この境界は変わりません。

## Troubleshooting

- Ollama の native readiness probe が `http://127.0.0.1:11434/api/version` で応答しない
  場合は、ホストの Ollama とモデル管理を修復します。WSL では Windows-host Ollama を
  修復し、WSL daemon を追加しません。これは MLflow trace の検証ではありません。
- MLflow Gateway が unavailable の場合は、`task mlflow:status`、`task mlflow:logs`、
  `task mlflow:verify` を実行します。Hindsight inference は direct host Ollama へ
  fail-open してはいけません。
- Hindsight API が `healthy` / `connected` を返さない場合は、`pg0` と `cache` の
  所有権・復元手順、および Hindsight のログを確認します。
- モデル取得または strict probe が失敗した場合は、`docker/hindsight/hindsight.env`
  の正確なモデル名と Ollama `/api/tags` を確認します。
- profile 間でメモリが見える疑いがある場合は、`task hermes:memory:verify` を実行し、
  全 7 bank の cross-profile rejection を確認します。
- Hindsight が unavailable の間に Hermes 自体が停止する場合は、degraded mode を
  再実行して gateway の one-shot と `/health` を確認します。
