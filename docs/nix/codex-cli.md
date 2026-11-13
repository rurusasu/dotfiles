# ChatGPT と同梱 Codex の管理

Codex CLI は各 OS 向け ChatGPT アプリ付属のものを使用します。Windows は Windows アプリの CLI、
NixOS / WSL は Linux アプリの CLI、macOS は macOS アプリの CLI です。installer では
`@openai/codex` を個別にインストールしません。

## モジュール構成

AI エージェントの設定はアプリ単位でまとめます。

```text
nix/modules/ai_agents/
├── mcp/      # 明示的に読み込む共通 MCP module
├── chatgpt/  # ChatGPT アプリ・同梱 Codex の設定
└── hermes/   # Hermes の公式 Home Manager 設定
```

`chatgpt/default.nix` はほかの実 module と同じく明示的に読み込まれ、型付き `programs.chatgpt.enable` と
標準 `programs.codex.enable` に従って導入・設定を管理します。アプリごとの import パスや公開一覧は登録しません。
`chatgpt/default.nix` 内で ChatGPT package を選び、同梱 CLI へのリンクを通常の Nix profile の
`bin/codex` に配置します。アプリ内部の PATH を継承しないターミナルや Sidekick からも検出できます。
同梱ツールの配置先も標準 `home.sessionPath` へ登録します。
`nix/home/<platform>.nix` は Darwin / native・standalone Linux で `programs.chatgpt.enable`、
WSL では `programs.codex.enable` を指定します。ChatGPT の有効化は同梱 Codex も有効にし、WSL には Linux GUI を導入しません。
Codex と ChatGPT Work の既定モデルは `gpt-6.1-terra`、通常・plan の reasoning effort は `ultra` です。
Pi は独立した `programs.pi-coding-agent.enable` で有効化し、既定の coding engine にローカル Strata を使います。
`nix/modules/ai_agents/pi/default.nix` が provider `strata`、モデル `qwen3.8-flash-next-q2_0`、
接続先 `http://127.0.0.1:8080/v1`、thinking level `off` を管理します。
context は32K、生成上限と compaction の予約は4096トークン、保持する直近履歴は8192トークンです。
`models.json` は Home Manager、可変の `settings.json` は Home Manager の既定値との merge で管理します。
Strata の起動と preset は [パッケージ管理](package-management.md) を参照してください。新規セッションは Strata を使い、既存セッションのモデルを変える場合は Pi の `/model` で選択します。
Windows の Store 導入情報は `chezmoi/winget/packages.json` で直接管理します。
Codex CLI を独立したパッケージとして導入しません。

## Darwin / Linux の公式版

共通の locked nixpkgs から `pkgs.chatgpt.override { codex = null; }` を利用します。
公式 `.deb` の取得・ELF 修正・プラグインキャッシュ・起動処理と、Darwin の公式署名保持・
package 内 install check の扱いは upstream の package 定義が所有します。
`codex = null` により、Linux の upstream が既定で行う独立 Codex package への置換を無効化します。
専用のビルドテストが store 確定後に
Home Manager と同じ方法でコピーしたアプリの署名・アプリの版・同梱 CLI の起動を検証します。
同梱 CLI と `codex-code-mode-host` があるディレクトリを PATH に登録します。
Linux の実行依存 `bubblewrap` は同じ module が導入します。
Darwin は公式 launcher の `Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`、
Linux は `lib/chatgpt/resources/codex` を使います。

Hyprland の AI キーと application launcher から起動できます。通常は XWayland を使い、
native Wayland を試す場合は `chatgpt --ozone-platform=wayland` で起動します。
OpenAI の Linux 版はプレビューで、NixOS は正式サポート対象外です。Linux の Computer Use と
native Wayland には制約があります。最新の範囲は [公式 Linux 版案内](https://learn.chatgpt.com/docs/linux/linux-app) を参照してください。

更新時は `nix flake update nixpkgs` で共通の nixpkgs lock を更新します。
同梱 CLI もアプリとともに更新されます。
通常の `task test:nix` は `custom-package-builds` 経由で
両 OS のアプリのビルド・同梱 CLI の起動、Linux の desktop entry を検証します。
単独では `nix build .#checks.x86_64-linux.chatgpt-desktop --no-link --no-write-lock-file` を使えます。
`aarch64-linux` のビルドには対応する builder が必要です。GUI のログイン・権限・操作は実機で確認します。

## 設定の所有

Unix の `CODEX_HOME` は `${config.xdg.configHome}/codex`（既定 `~/.config/codex`）です。
`home.preferXdgDirectories = true` により標準 module が XDG 配置を選びます。
macOS の GUI にも同じ `CODEX_HOME` を渡します。標準の `launchd.agents` を使い、
ログイン時にユーザー環境へ設定します。
Unix の config は `nix/modules/ai_agents/chatgpt/` の
Home Manager `programs.codex` が管理します。`programs.codex.enable = true` と `package = null` を指定し、
CLI のバージョン判定に依存せず設定を生成します。同梱 CLI の導入も同じ `default.nix` が `programs.codex.enable` に従って管理します。
WSL は Linux 版を使い、Windows は Windows 側のアプリを使います。
`mutableSettings = true` で既存の UI 設定や project trust を保持して宣言値をマージします。
認証ファイル・履歴・セッションは Home Manager の管理対象にしません。
Windows の設定は chezmoi が管理します。

管理スキルは `chatgpt/skills/` 直下の実ディレクトリから `SKILL.md` を持つものを自動登録します。
個別の名前を登録せず、Codex の共通指示は各スキルの description から適用対象を判断して読むよう指定します。

共通 MCP は `nix/modules/ai_agents/mcp/default.nix` の `programs.mcp.servers` を正本とし、
Codex は `enableMcpIntegration = true` で取り込みます。
Google 連携は Pipedream に統一し、Codex の Google curated plugins は宣言しません。
ユーザーが `codex mcp login pipedream` で OAuth を実行してください。
設定と認証の範囲は [Google MCP](../hermes-agent/gmail-mcp.md) を参照してください。

Unix の dsh の導入は `nix/home/common.nix` で管理します。
Windows では dsh・pnpm・Bun を導入しません。

## 反映

```bash
./install.sh
```

```powershell
.\install.cmd
Get-Command codex.exe -All
```

Windows の AppX 識別子は upstream の `OpenAI.Codex` を維持します。
