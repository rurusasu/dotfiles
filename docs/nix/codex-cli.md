# ChatGPT と同梱 Codex の管理

Codex CLI は各 OS 向け ChatGPT アプリ付属のものを使用します。Windows は Windows アプリの CLI、
NixOS / WSL は Linux アプリの CLI、macOS は macOS アプリの CLI です。installer では
`@openai/codex` を個別にインストールしません。

## モジュール構成

AI エージェントの設定はアプリ単位でまとめます。

```text
nix/modules/ai_agents/
├── chatgpt/  # ChatGPT アプリ・同梱 Codex の設定
└── hermes/   # Hermes gateway・CLI 設定・bootstrap manifest
```

`nix/modules/tools.nix` がアプリと CLI を選択します。Darwin と native NixOS は同じ
`chatgpt/packages.nix` からアプリと同梱 CLI を選び、WSL は同じ Linux package の CLI だけを選びます。
アプリは `home.packages`、CLI は標準 `programs.codex.package` で宣言し、CLI の PATH 配置と設定生成を
Home Manager に任せます。`chatgpt/desktop.nix` が Linux desktop のキャッシュ cleanup を設定します。
WSL には Linux GUI を導入しません。Darwin host は `tools.nix` の `chatgpt` module、native NixOS は
`nativeDesktop`、WSL は `chatgptCli` を選択します。
Windows の Store 導入・検証情報は `windows/winget/packages.json` で直接管理します。
Codex CLI を独立したパッケージとして導入しません。

## Darwin / native NixOS の公式版

Darwin / Linux 対応済みの nixpkgs を `chatgpt-nixpkgs` input に固定します。システム全体の nixpkgs は
更新せず、この input の package set をそのまま利用します。公式 `.deb` の取得・ELF 修正・
プラグインキャッシュ・起動処理は upstream の package 定義が所有します。
`chatgpt.override { codex = null; }` により、upstream の独立 Codex package への置換を無効化します。
端末の `codex` はアプリ内の実体を呼び出し、隣接する `codex-code-mode-host` を同じ配布物に保ちます。
CLI wrapper は `writeShellApplication` で実行依存と OS 別 resource path を宣言します。
Darwin は公式 launcher の `Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`、
Linux は `lib/chatgpt/resources/codex` を使います。wrapper の package version は同梱 CLI の
実バージョンを宣言し、Home Manager のバージョン別設定生成に利用します。
Linux のキャッシュ cleanup は upstream の規則を `systemd.user.tmpfiles.rules` に渡し、
設定ファイルの生成・反映と systemd 連携を Home Manager に任せます。Darwin に systemd 設定は生成しません。

Hyprland の AI キーと application launcher から起動できます。通常は XWayland を使い、
native Wayland を試す場合は `chatgpt --ozone-platform=wayland` で起動します。
OpenAI の Linux 版はプレビューで、NixOS は正式サポート対象外です。Linux の Computer Use と
native Wayland には制約があります。最新の範囲は [公式 Linux 版案内](https://learn.chatgpt.com/docs/linux/linux-app) を参照してください。

更新時は `flake.nix` の `chatgpt-nixpkgs` revision を対応済みの upstream revision に変更し、
`nix flake lock` を実行します。同梱 CLI の更新時は `packages.nix` の version も更新します。
通常の `task test:nix` は `custom-package-builds` 経由で
両 OS のアプリのビルド・同梱 CLI の起動と宣言 version の一致、Linux の desktop entry と tmpfiles を検証します。
単独では `nix build .#checks.x86_64-linux.chatgpt-desktop --no-link --no-write-lock-file` を使えます。
`aarch64-linux` のビルドには対応する builder が必要です。GUI のログイン・権限・操作は実機で確認します。

## 設定の所有

Unix の config・agents・rules・hooks は `nix/modules/ai_agents/chatgpt/` の
Home Manager `programs.codex` が管理します。Darwin / NixOS / WSL の `package` は各 OS 向け同梱 CLI の
wrapper を指定し、独立した Codex 配布物は導入しません。WSL は Linux 版を使い、Windows は Windows 側のアプリを使います。
`mutableSettings = true` で既存の UI 設定や project trust を保持して宣言値をマージします。
認証ファイル・履歴・セッションは Home Manager の管理対象にしません。
Windows の設定は chezmoi が管理します。

Unix の Node.js/npm と dsh の導入は `nix/modules/tools.nix` で管理します。
Windows の npm/pnpm manifest は空で、dsh を導入しません。pnpm と Bun は導入しません。

## 反映

```bash
./install.sh
```

```powershell
.\install.cmd
Get-Command codex.exe -All
```

Windows の AppX 識別子は upstream の `OpenAI.Codex` を維持します。
