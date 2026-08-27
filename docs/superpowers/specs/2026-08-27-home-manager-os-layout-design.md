# Home Manager OS別レイアウト設計

## Goal

`nix/home/` をOS単位で直接見つけられる構成へ整理し、共通設定とOS固有設定の依存方向をREADMEで明文化する。

## Current Problem

現在の `nix/home/` には、共通設定、OS別のユーザーマッピング、過去のWSL bootstrap用ファイルが混在している。

```text
nix/home/
├── common.nix
├── linux/users.nix
├── users/nixos.nix
└── wsl/
    ├── default.nix
    └── users.nix
```

現行flakeの経路は `linux/users.nix` と `wsl/users.nix` を直接使う一方、bootstrap scriptは `users/` と `wsl/default.nix` を生成対象としている。この差を解消する。

## Target Architecture

```text
nix/home/
├── README.md
├── common.nix
├── darwin.nix
├── linux.nix
└── wsl.nix
```

- `common.nix` は全プラットフォームで共有するHome Manager module。
- `darwin.nix`、`linux.nix`、`wsl.nix` はOS固有のHome Manager module。
- 各OS moduleは `./common.nix` をimportする。
- 共通moduleはOS moduleを参照しない。
- OS moduleは必要なOS固有差分だけを追加する。
- `nix/home/default.nix` は作成しない。`nix/home/` 自体をimportせず、各OS fileを明示的にimportするためである。
- `users.nix` はNixの予約名ではないため、ユーザー名マッピングとmoduleの責務を分離する。

依存方向は次に固定する。

```text
flake / host wiring
        ↓
darwin.nix / linux.nix / wsl.nix
        ↓
common.nix
```

## Wiring Changes

- `nix/flakes/hosts.nix` はWSLに `../home/wsl.nix`、native Linuxに `../home/linux.nix` を渡す。
- NixOSのHome Manager wiringは、OS moduleをユーザーへ適用する。OS module自身はユーザー名マッピングを返さない。
- `nix/flakes/home.nix` はDarwinで `../home/darwin.nix`、Linuxで `../home/linux.nix` を使う。
- `nix/hosts/darwin/default.nix` は `../../home/darwin.nix` をHome Manager user moduleとして使う。
- `nix/system-manager/default.nix` はLinux moduleを使う。
- `isWSL` などのspecial argumentは各呼び出し側が引き続き与える。

## Bootstrap and Compatibility

`nixos-wsl-postinstall.sh` は、リポジトリ内に存在しない `nix/home/users/<user>.nix` や旧形式の `nix/home/wsl/default.nix` を新規生成しない。既存のホスト・ユーザー・ハードウェア生成処理は維持し、Home Managerの参照だけをcanonicalなOS moduleへ変更する。

旧ファイルを削除する場合は、同じ変更で全参照を更新し、`rg`で旧パスが残っていないことを確認する。未管理のユーザー設定を上書きしないbootstrapの安全性は維持する。

## README Rules

`nix/home/README.md` に次を記載する。

1. `nix/home/` はHome Managerのユーザー環境を管理し、実際の `~/` の原本全体やsecretを保存しない。
2. 共通設定は `common.nix`、OS固有設定は `<os>.nix` に置く。
3. `<os>.nix` から `./common.nix` をimportし、`common.nix`からOS moduleをimportしない。
4. OSごとに単一fileであるため、`default.nix` やOS別subdirectoryは作らない。
5. パッケージのSSOTは `nix/packages/sets.nix`、設定ファイルの原本は `chezmoi/` とする。
6. 新しいOS固有設定を追加するときは、対応するOS file、caller、テスト、READMEを同じ変更で更新する。

## Validation

- `rg`で旧パスと旧importが残っていないことを確認する。
- `nix flake check` を実行する。
- 既存のflake output、Linux/WSL/macOS configuration、Home Manager wiringのBatsテストを実行する。
- `nix/home/README.md` と実際の構成・import経路を照合する。
