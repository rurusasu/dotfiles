# openclaw Docker: 実装時の必須ルール

このディレクトリは、openclaw (Telegram AI gateway) を Docker で動かすための構成を管理する。

## 変更時に必ず触るファイル

- `docker/openclaw/Dockerfile`
- `docker/openclaw/docker-compose.yml`
- `docker/openclaw/entrypoint.sh`
- `docker/openclaw/acpx.config.json`
- `docker/openclaw/gemini.settings.json`
- `docker/openclaw/.env`（通常は自動生成。手動編集は最小限）
- `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`（設定の source of truth）

## 起動と再生成の正規フロー

`scripts/powershell/install.user.ps1` (Handler.OpenClaw.ps1) が以下を一括実行する。

1. `chezmoi apply` で設定を展開
2. `.env` を生成（`OPENCLAW_CONFIG_FILE` など。PAT は含めない）
3. 1Password から GitHub PAT を取得し、`~/.openclaw/secrets/github_token` を更新
4. `docker compose up -d --build` で起動

通常の起動・復旧はこのコマンドを使う。

```powershell
pwsh -File scripts/powershell/install.user.ps1
```

## 設定値の流れ（変更影響の把握用）

```text
1Password secret
  -> chezmoi template (dot_openclaw/openclaw.docker.json.tmpl)
  -> ~/.openclaw/openclaw.docker.json
  -> container: /home/bun/.openclaw/openclaw.json (read-only bind)
```

1Password の値変更後は再展開してコンテナ再起動する。

```powershell
chezmoi apply
docker restart openclaw
```

## セキュリティ制約（設計前提）

`docker-compose.yml` は以下前提で維持する。

- `read_only: true`
- `tmpfs: /tmp`
- `cap_drop: [ALL]`
- `security_opt: no-new-privileges:true`
- `user: "1000:1000"`

つまり、コンテナ内で永続的に書き込めるのは volume と tmpfs のみ。

## 必須ボリューム（書き込み先）

- `openclaw-home` -> `/home/bun/.openclaw`（openclaw state）
- `openclaw-acpx` -> `/home/bun/.acpx`（acpx runtime state）
- `openclaw-data` -> `/app/data`（workspace / skills / .bun）
- bind mount -> `/home/bun/.openclaw/openclaw.json`（config read-only）

## GitHub 認証の実装ルール

- 認証方式は Fine-grained PAT のみ（Classic PAT 不使用）
- PAT は 1Password から起動時に取得し、Docker secret `github_token` として注入
- コンテナ内 git 認証は `GIT_ASKPASS=/usr/local/bin/git-credential-askpass.sh` を使う
- `entrypoint.sh` が `/run/secrets/github_token` を読み、`GITHUB_TOKEN` と `GH_TOKEN` をプロセス環境へ export
- `Dockerfile` 側で `git-credential-askpass.sh` を配置する

1Password 参照先:

```text
op://Personal/GitHubUsedOpenClawPAT/credential
```

`.env` が既にある場合、Handler の `EnsureEnvFile` は再生成をスキップする。再生成したい場合:

```powershell
Remove-Item docker\openclaw\.env
pwsh -File scripts\powershell\install.user.ps1
```

手動起動する場合は `OPENCLAW_GITHUB_TOKEN_FILE` をセットする。
（Handler は `~/.openclaw/secrets/github_token` を自動設定する）

## 手動操作コマンド（Handler 非経由時）

```powershell
docker compose -f docker/openclaw/docker-compose.yml up -d --build
docker compose -f docker/openclaw/docker-compose.yml down
docker compose -f docker/openclaw/docker-compose.yml logs -f
docker exec -it openclaw sh
```

## 既知障害の一次切り分け

- `acpx exited with code 1`
  - `openclaw-acpx` が `/home/bun/.acpx` に mount され、書き込み可能か確認
- `Invalid JSON in /home/bun/.acpx/config.json`
  - `config.json` の途中切れ（0 byte / 壊れ JSON）を疑う
  - `entrypoint.sh` が `/app/acpx.config.json` を起動時に再投入する設計なので、`docker compose up -d --build --force-recreate` を優先
  - コンテナ内確認: `cat /home/bun/.acpx/config.json`
- `acpx: not found`
  - `openclaw.docker.json` の `plugins.entries.acpx.config.command` を `/usr/local/bin/acpx` に固定
- `sessions_spawn(runtime:"acp")` が initialize で詰まる
  - `acpx.config.json` の `agents.gemini.command` を `gemini --experimental-acp` に固定（デフォルト `gemini` のままだと ACP ハンドシェイク未成立）
- `sessions_spawn(runtime:"acp")` が 429 で失敗
  - ローカル設定不備ではなく Gemini 側の一時容量制限 (`MODEL_CAPACITY_EXHAUSTED`) を疑う
- `plugin telegram: duplicate plugin id`
  - `/home/bun/.openclaw/extensions/telegram` の旧拡張を退避/削除し、stock 側のみ利用

## サブエージェント完了判定の運用ルール

- announce は `best-effort` のため、完了判定の唯一ソースにしない
- `sessions_spawn` 後は `runId` / `childSessionKey` を保持し、`sessions_history` か `/subagents info` で状態確認する
- 追跡不能が起きる場合は `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` で以下を確認する
  - `agents.defaults.subagents.maxSpawnDepth = 2`
  - `agents.defaults.sandbox.sessionToolsVisibility = "all"`
  - `tools.sessions.visibility = "tree"`

参照:

- https://docs.openclaw.ai/tools/subagents
- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/tools
