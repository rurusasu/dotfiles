# Hermes Hindsight ローカルメモリ運用

## Architecture

Hindsight は Hermes から独立したホスト共通の永続メモリサービスです。ホストで動く
Ollama を推論・埋め込みに使い、Compose の `hindsight` サービスが埋め込み
PostgreSQL、ローカル reranker、メモリ API を提供します。独立 Compose project が
`dotfiles-memory` ネットワークを所有し、Hermes は external network として接続して
`http://hindsight:8888` を使います。

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

## Installation

Windows では `-WithDocker` または `-WithHermes` を指定すると、Ollama、Docker、
独立 Hindsight が順に有効になります。Hindsight 単体の通常の操作入口は次です。

```text
task hindsight:up
```

この処理は独立 Compose を検証し、ホスト Ollama へモデルを取得し、
`${HINDSIGHT_DATA_DIR:-~/.local/share/hindsight}/pg0` と `cache` を作成してから
Hindsight だけを起動します。Hermes の起動・停止は行いません。

旧構成の `${HERMES_DATA_DIR:-~/.hermes}/hindsight` が存在し、新しい保存先にまだ
メモリがない場合、初回起動は旧 `hermes-hindsight` container を停止し、旧 `pg0` と
`cache` を staging 経由で新しい保存先へコピーしてから旧 container を削除します。
コピー元は rollback 用に残し、新保存先の marker により2回目以降は移行を
繰り返しません。旧保存先と新保存先の両方にデータがある場合は自動上書きや併合を
せず、起動前に明示的に失敗します。受入検証の state/evidence は移行対象外です。

## Model inventory

モデルと Hindsight の非秘密ランタイム設定のソースは
`docker/hindsight/hindsight.env` です。現在のモデルは次のとおりです。

| 用途     | 値                                        |
| -------- | ----------------------------------------- |
| LLM      | `qwen3.6:35b`                             |
| 埋め込み | `qwen3-embedding:0.6b`                    |
| reranker | `BAAI/bge-reranker-v2-m3`（ローカル CPU） |

ホスト準備は `qwen3.6:35b` と `qwen3-embedding:0.6b` を取得します。Hindsight は Ollama OpenAI 互換
エンドポイント `http://host.docker.internal:11434/v1` を使います。

## Startup

通常の起動入口は次です。

```text
task hindsight:up
```

起動の成否はポートの listen だけで判断せず、`/health` の `status` が
`healthy` かつ `database` が `connected` であることを確認します。

## Status

サービス状態と API ヘルスは次で確認します。

```text
task hindsight:status
curl --fail --silent --show-error http://127.0.0.1:8888/health
```

既定の公開先は次のとおりです。環境変数でポートを変更している場合は、その値を
使います。

| 対象          | 既定の URL               |
| ------------- | ------------------------ |
| Ollama API    | `http://127.0.0.1:11434` |
| Hindsight API | `http://127.0.0.1:8888`  |
| Hindsight UI  | `http://127.0.0.1:9999`  |

## Logs

Hindsight の直近ログを追跡するには次を使います。

```text
task hindsight:logs
```

Hermes gateway 側の状態も同時に確認する場合は、`task hermes:logs` を使います。
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
成功時の evidence は `/opt/data/hindsight/acceptance.json`、実行中の state は
`/opt/data/hindsight/acceptance-state.json` です。失敗時は診断のため failed-run
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
python3 -m unittest discover -s docker/hermes-agent/bootstrap/tests -p 'test_*contract.py' -v
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

- Ollama API が `http://127.0.0.1:11434/api/version` で応答しない場合は、ホストの
  native Ollama を修復します。WSL では Windows-host Ollama を修復し、WSL daemon を
  追加しません。
- Hindsight API が `healthy` / `connected` を返さない場合は、`pg0` と `cache` の
  所有権・復元手順、および Hindsight のログを確認します。
- モデル取得または strict probe が失敗した場合は、`docker/hindsight/hindsight.env`
  の正確なモデル名と Ollama `/api/tags` を確認します。
- profile 間でメモリが見える疑いがある場合は、`task hermes:memory:verify` を実行し、
  全 7 bank の cross-profile rejection を確認します。
- Hindsight が unavailable の間に Hermes 自体が停止する場合は、degraded mode を
  再実行して gateway の one-shot と `/health` を確認します。
