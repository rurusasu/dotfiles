# nix/hosts: OS 別システム定義

## 構成

- `default.nix`: host 構築関数と OS 別 runner、native / standalone Linux 共通の Home Manager module `linuxHome`。CPU architecture は `system` 引数で選択する。
- `configurations.nix`: Darwin / NixOS / standalone Home Manager の構成登録と GC 方針。実行間隔・削除オプション・Darwin の空き容量条件をここに集約し、統合構成は system GC、standalone は user GC に渡す。root の `flake.nix` から読み込む。
- `darwin.nix`: macOS の system、account、service、Homebrew、system font、activation と Home Manager 統合。
- `darwin-app-cleanup.nix`: macOS の同梱アプリを整理する package factory。
- `nixos.nix`: native NixOS / WSL 共通の account、system module、Docker、Home Manager 統合と `system.stateVersion = "26.05"`。
- `identity.nix`: NixOS のユーザー・UID/GID・ホーム・checkout などのホスト情報。
- `linux.nix`: native NixOS のデスクトップセッションと Hyprland の選択。
- `wsl.nix`: WSLg、Windows interop、WSLg 向けフォント配布などの WSL system 連携。

標準レイアウトは次のとおりです。

```text
nix/hosts/
├── default.nix
├── configurations.nix
├── darwin.nix
├── darwin-app-cleanup.nix
├── nixos.nix
├── identity.nix
├── linux.nix
└── wsl.nix
```

system module はこのディレクトリ直下に置き、CPU ごとの違いは `system` 引数で扱う。
`linux.nix` と `wsl.nix` は共通の `nixos.nix` を読み込む。
Home Manager の OS 設定は Darwin / WSL が `nix/home/{darwin,wsl}.nix`、
native / standalone Linux が `default.nix` の `linuxHome`、共通設定は
`nix/home/common.nix` が所有する。`linuxHome` は Home Manager の scope でユーザー情報・GUI 選択・Git 署名を設定する。
Darwin の Dock・Finder・trackpad などのユーザー defaults と
反映 activation は `nix/home/darwin.nix`、AeroSpace とユーザーキー設定は
`nix/home/keybindings/darwin.nix`、ユーザー cache 整理は `nix/home/darwin.nix` に置く。
WSL の環境変数・VS Code Server・`op` 連携は `nix/home/wsl.nix`、署名スクリプトは
`nix/home/op-ssh-sign-wsl`、fontconfig asset は `nix/modules/fonts/wsl-fontconfig.conf` が所有する。

`hardware-configuration.nix` は全 host に必要な標準ファイルではない。native NixOS の実機では、
マシンごとの `/etc/nixos/hardware-configuration.nix` を Nix 側で検出して
読み込む。ユーザーと UID/GID は `identity.nix` が既存アカウントから取得する。複数の実機で同じ host profile を使う場合も、hardware configuration は各マシン固有にする。
NixOS-WSL では通常不要で、Darwin では使用しない。

Windows の導入は `windows/winget/packages.json`、ユーザー設定は `chezmoi/` が所有する。Nix から Windows デスクトップ設定を生成しない。

## ルール

- OS 非依存で再利用するアプリ・機能設定は `nix/modules/`、OS の system 設定は `nix/hosts/*.nix`、共通・Darwin・WSL の Home Manager ユーザー設定・ユーザーサービスは `nix/home/`、Linux 共通の Home Manager module は `default.nix` の `linuxHome` に置く。
- キー配置の共通 action/key と設定生成関数は `nix/home/keybindings/` に置く。`nix/home/keybindings/darwin.nix` は Home Manager module として純粋な設定生成関数を読み、AeroSpace・launchd・ユーザー shortcut の競合解除を管理する。`nix/hosts/linux.nix` は native NixOS のセッションを有効化し、ユーザー設定の Home Manager module を選択して読み込む。
- データと host 動作を分けて OS 間の重複を防ぐ。責務と WSL 境界は [Omarchy 配列](../../docs/chezmoi/omarchy.md) を参照する。
