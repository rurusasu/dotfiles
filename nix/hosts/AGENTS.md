# nix/hosts: ホスト別システム定義

## 構成

- `<host>/default.nix`: host の entrypoint。`configuration.nix` と共通 module を import する
- `<host>/configuration.nix`: system、service、user、cask、activation などのホスト固有設定

標準レイアウトは次のとおりです。

```text
nix/hosts/<host>/
├── default.nix
└── configuration.nix
```

Darwin も例外にせず、`nix/hosts/darwin/default.nix` を flake の entrypoint とし、実体は
`nix/hosts/darwin/configuration.nix` に置く。`default.nix` に system option を直接追加しない。

`hardware-configuration.nix` は全 host に必要な標準ファイルではない。native NixOS の実機では、
マシンごとの `/etc/nixos/hardware-configuration.nix` を `DOTFILES_NIXOS_HARDWARE_CONFIG` 経由で
読み込む。複数の実機で同じ host profile を使う場合も、hardware configuration は各マシン固有にする。
NixOS-WSL では通常不要で、Darwin では使用しない。

`windows/` は NixOS/nix-darwin の system host ではなく、Windows デスクトップの設定出力と起動処理を持つ。`omarchy-keybindings.nix` を通常の Nix `import` で呼び、生成物を chezmoi 経由で配布する。上記の `default.nix` / `configuration.nix` 構成は適用しない。

## ルール

- 共通化できる内容は `nix/modules/` へ移す。
- キー配置の共通 action/key とユーザー設定は `nix/home/keybindings/` に置く。host の `omarchy-keybindings.nix` は OS の service/有効化・競合解除を担当する。Darwin と Windows は純粋な設定生成関数を通常の import で呼び、native NixOS は Home Manager module を選択して読み込む。
- データと host 動作を分けて OS 間の重複を防ぐ。責務と WSL 境界は [Omarchy 配列](../../docs/chezmoi/omarchy.md) を参照する。
