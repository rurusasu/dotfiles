# nix/hosts: ホスト別システム定義

## 構成

- `<host>/default.nix`: host の entrypoint。`configuration.nix` と共通 module を import する
- `<host>/configuration.nix`: system、service、user、cask、activation などのホスト固有設定
- `<host>/hardware-configuration.nix`: NixOS ハードウェア設定

標準レイアウトは次のとおりです。

```text
nix/hosts/<host>/
├── default.nix
└── configuration.nix
```

Darwin も例外にせず、`nix/hosts/darwin/default.nix` を flake の entrypoint とし、実体は
`nix/hosts/darwin/configuration.nix` に置く。`default.nix` に system option を直接追加しない。

## ルール

- 共通化できる内容は `nix/modules/` へ移す。
