# ChatGPT と同梱 Codex の管理

Codex CLI は ChatGPT アプリ付属のものを使用します。Windows、WSL/NixOS、macOS の
installer では `@openai/codex` を個別にインストールしません。

## モジュール構成

AI エージェントの設定はアプリ単位でまとめます。

```text
nix/modules/ai_agents/
├── chatgpt/  # ChatGPT アプリ・同梱 Codex の設定・Windows 配布 metadata
└── hermes/   # Hermes CLI・gateway・bootstrap manifest
```

ChatGPT アプリは `chatgpt/default.nix` が macOS の `home.packages` に直接導入します。
Windows の Store 配布・検証・CI 設定は `chatgpt/windows-install.nix` が管理します。
パッケージカタログには登録しません。
Codex CLI を独立したパッケージとして導入しません。

## 設定の所有

Unix の config・agents・rules・hooks は `nix/modules/ai_agents/chatgpt/` の
Home Manager `programs.codex` が管理します。`package = null` により CLI の重複導入を防ぎます。
`mutableSettings = true` で既存の UI 設定や project trust を保持して宣言値をマージします。
認証ファイル・履歴・セッションは Home Manager の管理対象にしません。
Windows の設定は chezmoi が管理します。

Node.js/npm はパッケージカタログで管理し、dsh は Unix では `nix/modules/dsh.nix`、
Windows では生成した `windows/npm/packages.json` で導入します。pnpm と Bun は導入しません。

## 反映

```bash
./install.sh
```

```powershell
.\install.cmd
Get-Command codex.exe -All
```

Windows の AppX 識別子は upstream の `OpenAI.Codex` を維持します。
