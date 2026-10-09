# nix/hosts: ホスト別システム定義

## 構成

- `nix/hosts/default.nix`: host 構築関数と OS 別 runner。
- `nix/hosts/configurations.nix`: Darwin / NixOS / standalone Home Manager の構成登録。root の `flake.nix` から読み込む。

- `<system>/default.nix` または `<system>/<environment>/default.nix`: host entrypoint。設定 module を import する。
- `configuration.nix`: system、service、user、cask、activation などの環境固有設定。
- `home.nix`: OS 固有の Home Manager 設定・ユーザーパッケージ選択。OS 非依存の設定は `nix/home/common.nix` から読み込む。
- `system.nix`: 必要な host で分離する OS-wide defaults。Darwin では timezone と defaults の反映 activation も所有する。
- `platform.nix`: OS option と共通 module の配線。Darwin は `aarch64-darwin/`、NixOS/WSL 共通部分は `shared/nixos/` が所有する。
- `x86_64-linux/wsl/integration.nix`: WSLg、Windows interop、1Password、Docker などの WSL 固有連携。
- `shared/linux-home.nix`: x86_64 / aarch64 の Linux Home Manager 共通設定。
- `shared/nixos/`: native NixOS の共通システム設定。各 system の `nixos/default.nix` から読み込む。

標準レイアウトは次のとおりです。

```text
nix/hosts/
├── default.nix
├── configurations.nix
├── aarch64-darwin/        # default.nix / configuration.nix / home.nix / system.nix
├── x86_64-linux/         # home.nix / nixos/default.nix / wsl/
├── aarch64-linux/        # home.nix / nixos/default.nix
├── shared/              # linux-home.nix / nixos/
└── windows/             # Windows 設定生成・起動処理
```

Darwin も例外にせず、`nix/hosts/aarch64-darwin/default.nix` を flake の entrypoint とし、実体は
`nix/hosts/aarch64-darwin/configuration.nix` と責務別 module に置く。host identity、サービス、Homebrew、
統合固有の activation は `configuration.nix`、system font は `nix/modules/fonts.nix` の定義を `platform.nix` から配布し、OS-wide defaults、
timezone、defaults の反映 activation は `system.nix` が所有する。
Darwin の `default.nix` は配線専用とし、必要な module を import する。system option を直接追加しない。

`hardware-configuration.nix` は全 host に必要な標準ファイルではない。native NixOS の実機では、
マシンごとの `/etc/nixos/hardware-configuration.nix` を `DOTFILES_NIXOS_HARDWARE_CONFIG` 経由で
読み込む。複数の実機で同じ host profile を使う場合も、hardware configuration は各マシン固有にする。
NixOS-WSL では通常不要で、Darwin では使用しない。

`windows/` は NixOS/nix-darwin の system host ではなく、Windows デスクトップの設定出力と起動処理を持つ。`omarchy-keybindings.nix` を通常の Nix `import` で呼び、生成物を chezmoi 経由で配布する。上記の `default.nix` / `configuration.nix` 構成は適用しない。

## ルール

- OS 非依存で再利用するアプリ・機能設定は `nix/modules/`、OS 固有の共通設定は `nix/hosts/shared/` に置く。
- キー配置の共通 action/key とユーザー設定は `nix/home/keybindings/` に置く。host の `omarchy-keybindings.nix` は OS の service/有効化・競合解除を担当する。Darwin と Windows は純粋な設定生成関数を通常の import で呼び、native NixOS は Home Manager module を選択して読み込む。
- データと host 動作を分けて OS 間の重複を防ぐ。責務と WSL 境界は [Omarchy 配列](../../docs/chezmoi/omarchy.md) を参照する。
