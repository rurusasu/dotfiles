# nix/hosts: 統合済みのホスト定義

ホスト定義、ユーザー情報の検出、公開構成は `../default.nix` に統合しています。
このディレクトリに Nix 定義や転送用 wrapper を追加しません。

- `hostModules`: Darwin / NixOS 共通 / native Linux / WSL のシステム設定。
- native NixOS のアカウントは`hostModules.nixos` 内の検出処理、WSL は標準の `wsl.defaultUser` から決める。
- `homeModules`: 共通・Darwin・Linux・WSL の Home Manager 設定。
- `configurations`: 標準の NixOS / nix-darwin / Home Manager 構成。
- `perSystem`: 公開 app と package。

共通の Lix・OS GC・Home Manager 接続は内部の `systemDefaults`、GC 日時は OS module、standalone GC は `homeModules.common` が担当する。

CPU は `system` 引数で選択します。外部の実機 hardware configuration は従来どおり検出して読み込みます。
アプリ固有設定は `../modules/`、キー配列の補助 module と生成関数は `../home/keybindings/` が所有します。
