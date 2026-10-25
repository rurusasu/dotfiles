# nix/hosts: 統合済みのホスト定義

ホスト定義と公開構成は `../defaults.nix` に統合しています。
このディレクトリに Nix 定義や転送用 wrapper を追加しません。

- ユーザー名・stateVersion は `systemDefaults` 内の `defaults` で一元管理し、`_module.args` と Home Manager 共通設定から参照する。
- `systemDefaults`: 共通設定と末尾の OS 別 system imports。Home Manager の共通・OS 別設定は同じ `home-manager.sharedModules` にまとめる。
- `configurations`: 標準の NixOS / nix-darwin / Home Manager 構成。
- `perSystem`: 公開 app と package。

末尾の構成登録が `specialArgs.platform` を選択し、standalone Home Manager も同じ `sharedModules` を再利用する。

共有宣言を先に置き、OS 別宣言、公開構成の順に記載します。CPU は `system` 引数で選択します。
native 構成は `/etc/nixos/hardware-configuration.nix` がある場合だけ公開します。
アプリ固有の設定・サービス・activation・キー設定生成関数は `../modules/` に置きます。
`../defaults.nix` は OS 基盤設定と module 選択、`../home/keybindings/` は共通配列と Windows export を所有します。
