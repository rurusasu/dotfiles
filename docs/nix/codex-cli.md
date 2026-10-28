# ChatGPT と同梱 Codex の管理

Codex CLI は各 OS 向け ChatGPT アプリ付属のものを使用します。Windows は Windows アプリの CLI、
NixOS / WSL は Linux アプリの CLI、macOS は macOS アプリの CLI です。installer では
`@openai/codex` を個別にインストールしません。

## モジュール構成

AI エージェントの設定はアプリ単位でまとめます。

```text
nix/modules/ai_agents/
├── mcp/      # 自動検出する共通 MCP module
├── chatgpt/  # ChatGPT アプリ・同梱 Codex の設定
└── hermes/   # Hermes の公式 Home Manager 設定
```

`chatgpt/default.nix` はほかの実 module と同じく自動検出され、型付き `programs.chatgpt.enable` と
標準 `programs.codex.enable` に従って導入・設定を管理します。アプリごとの import パスや公開一覧は登録しません。
通常の `chatgpt/package.nix` factory が返す ChatGPT package と同梱 CLI へのリンクを使い、CLI の PATH 配置は Home Manager に任せます。
`nix/defaults.nix:systemDefaults` は Darwin / native・standalone Linux で `programs.chatgpt.enable`、
WSL では `programs.codex.enable` を指定します。ChatGPT の有効化は同梱 Codex も有効にし、WSL には Linux GUI を導入しません。
Codex と ChatGPT Work の既定モデルは `gpt-6.1-terra`、通常・plan の reasoning effort は `ultra` です。
Pi は独立した `programs.pi-coding-agent.enable` で有効化し、provider `openai-codex`、モデル `gpt-6.1-terra`、thinking level `max` を使います。
Windows の Store 導入情報は `windows/winget/packages.json` で直接管理します。
Codex CLI を独立したパッケージとして導入しません。

## Darwin / Linux の公式版

共通の locked nixpkgs から `pkgs.chatgpt.override { codex = null; }` を利用します。
公式 `.deb` の取得・ELF 修正・プラグインキャッシュ・起動処理と、Darwin の公式署名保持・
package 内 install check の扱いは upstream の package 定義が所有します。
`codex = null` により、Linux の upstream が既定で行う独立 Codex package への置換を無効化します。
専用のビルドテストが store 確定後に
Home Manager と同じ方法でコピーしたアプリの署名・アプリの版・同梱 CLI の起動を検証します。
`codex` は `pkgs.linkFarm` で `bin/codex` と `bin/codex-code-mode-host` を
アプリ内の実体への symlink として公開します。Linux では `bin/bwrap` も提供します。
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
Unix の config は `nix/modules/ai_agents/chatgpt/` の
Home Manager `programs.codex` が管理します。`programs.codex.enable = true` と `package = null` を指定し、
CLI のバージョン判定に依存せず設定を生成します。同梱 CLI の導入も同じ `default.nix` が `programs.codex.enable` に従って管理します。
WSL は Linux 版を使い、Windows は Windows 側のアプリを使います。
`mutableSettings = true` で既存の UI 設定や project trust を保持して宣言値をマージします。
認証ファイル・履歴・セッションは Home Manager の管理対象にしません。
Windows の設定は chezmoi が管理します。

Home Manager activation の `codexXdgHome` は、既存の認証・履歴を引き継ぐため、旧 `~/.codex` の実ディレクトリを XDG 配置先へ移し、旧パスに互換 symlink を作成します。新規環境では配置先と互換 symlink を作成します。両方に実ディレクトリがある場合や、旧 symlink が別のディレクトリを指す場合は、上書きせず反映を停止します。この処理は activation 時にのみ実行します。

共通 MCP は `nix/modules/ai_agents/mcp/default.nix` の `programs.mcp.servers` を正本とし、
Codex は `enableMcpIntegration = true` で取り込みます。
Google 連携は Pipedream に統一し、Codex の Google curated plugins は宣言しません。
ユーザーが `codex mcp login pipedream` で OAuth を実行してください。
設定と認証の範囲は [Google MCP](../hermes-agent/gmail-mcp.md) を参照してください。

Unix の dsh の導入は `nix/defaults.nix` で管理します。
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
