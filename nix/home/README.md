# Home Manager レイアウト

`nix/home/` はユーザー単位の Home Manager 設定です。

| 入口         | 内容           |
| ------------ | -------------- |
| `darwin.nix` | macOS 固有設定 |
| `linux.nix`  | Linux 固有設定 |
| `wsl.nix`    | WSL 固有設定   |
| `common.nix` | 共通設定       |

## import 方向

```text
caller -> <os>.nix -> common.nix
```

- caller は対象 OS のファイルだけを import する。
- 各 OS ファイルは `./common.nix` を import する。
- `common.nix` から OS 固有ファイルを import しない。
- `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

ユーザー名とホームディレクトリは `DOTFILES_USER` / `DOTFILES_HOME` から取得する。
NixOS は `DOTFILES_USER` 未指定時に `nixos` を使う。WSL postinstall は `--user` で選択した
ユーザーの `DOTFILES_USER` / `DOTFILES_HOME` / `DOTFILES_UID` / `DOTFILES_GID` /
`DOTFILES_GROUP` を export し、`nixos-rebuild` を `--impure` 付きで実行する。これにより
flake 評価中の `builtins.getEnv` が選択した識別情報を読み取り、NixOS host、Home Manager、
`wsl.defaultUser` の対象を一致させる。
`nrs` / `nrt` / `nrb` は `scripts/sh/nixos-rebuild-with-user.sh` 経由で実行し、同じ識別情報を
flake 評価へ渡す。

## Home Manager 固有のチェック

- OS 固有設定は対象 OS の Home Manager ファイルに追加し、`common.nix` に OS 条件を増やさない。
- Nix option、package、session variable のテストは `nix/tests/` に追加し、
  `nix flake check --all-systems --no-write-lock-file` と focused `nix-unit` build を実行する。
- Bats は Home Manager option の値を検査する用途には使わず、installer、shell、外部プロセス、
  runtime 契約に限る。
