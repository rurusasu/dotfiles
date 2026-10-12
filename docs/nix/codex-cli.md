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
native NixOS は host が `chatgpt/desktop.nix` を読み込み、`packages.nix` が公式 Linux 版と
同梱 CLI の wrapper を導入します。WSL には Linux GUI を導入しません。
Windows の Store 配布・検証・CI 設定は `chatgpt/windows-install.nix` が管理します。
パッケージカタログには登録しません。
Codex CLI を独立したパッケージとして導入しません。

## native NixOS の Linux 版

Linux 対応済みの nixpkgs を `chatgpt-nixpkgs` input に固定します。システム全体の nixpkgs は
更新せず、この input の package set をそのまま利用します。公式 `.deb` の取得・ELF 修正・
プラグインキャッシュ・起動処理は upstream の package 定義が所有します。
`chatgpt.override { codex = null; }` により、upstream の独立 Codex package への置換を無効化します。
端末の `codex` はアプリ内の実体を呼び出し、隣接する `codex-code-mode-host` を同じ配布物に保ちます。
書き込み可能なプラグインキャッシュの cleanup は upstream の user tmpfiles 定義を配布します。

Hyprland の AI キーと application launcher から起動できます。通常は XWayland を使い、
native Wayland を試す場合は `chatgpt --ozone-platform=wayland` で起動します。
OpenAI の Linux 版はプレビューで、NixOS は正式サポート対象外です。Linux の Computer Use と
native Wayland には制約があります。最新の範囲は [公式 Linux 版案内](https://learn.chatgpt.com/docs/linux/linux-app) を参照してください。

更新時は `flake.nix` の `chatgpt-nixpkgs` revision を対応済みの upstream revision に変更し、
`nix flake lock` を実行します。通常の `task test:nix` は `custom-package-builds` 経由で
アプリのビルド・同梱 CLI の起動・desktop entry と tmpfiles の存在を検証します。
単独では `nix build .#checks.x86_64-linux.chatgpt-desktop --no-link --no-write-lock-file` を使えます。
`aarch64-linux` のビルドには対応する builder が必要です。GUI のログイン・権限・操作は実機で確認します。

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
