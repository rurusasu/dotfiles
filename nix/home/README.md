# Home Manager の構成

`default.nix` は全環境共通の `common.nix` を読み込みます。
`settings.nix` はユーザー名を所有し、各 stateVersion は root の `flake.nix` に一元化します。
OS 別の home ファイルやアプリの有効化一覧は作りません。

アプリの有効化・package・設定・OS 差分・専用の実行依存は各 `../modules/` が所有し、
原則として module 内で `programs.<name>.enable = true` を宣言します。
`../modules/default.nix` の imports は明示的に管理します。

OS 基盤設定は `../hosts/`、Windows の設定とパッケージ情報は `../../chezmoi/`、
共通キー配列は `keybindings/`、公開 Home Manager 構成の組み立ては `configurations.nix` です。

OS 統合時はユーザー名・ホーム・Nix package を OS から継承し、OS が nix.conf と GC を所有します。
Home Manager 単独構成は共通設定からユーザーの nix.conf と GC を生成します。
検証の配置と実行手順は [Nix テスト](../tests/README.md) を参照してください。
