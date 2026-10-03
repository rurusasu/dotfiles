# Home Manager レイアウト

`nix/home/` はユーザー単位の Home Manager 設定です。

| 入口         | 内容                                        |
| ------------ | ------------------------------------------- |
| `darwin.nix` | macOS 固有設定                              |
| `linux.nix`  | Linux 固有設定                              |
| `wsl.nix`    | WSL 固有設定                                |
| `nixos.nix`  | native NixOS / WSL 共通の Home Manager 設定 |
| `common.nix` | 共通設定                                    |

## import 方向

```text
caller -> <os>.nix -> common.nix
```

- caller は対象 OS のファイルだけを import する。
- 各 OS ファイルは `./common.nix` を import する。
- Neovim は `darwin.nix` と `nixos.nix` が `../modules/nvim` を import する。`linux.nix` と `wsl.nix` は `nixos.nix` を経由する。
- `common.nix` から OS 固有ファイルを import しない。
- `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

standalone Home Manager のユーザー名は `rurusasu` を既定値とする。ホームディレクトリは OS 別ファイルで
既定化する。nix-darwin / NixOS の Home Manager submodule は host の
`users.users.<name>.home` を使う。
NixOS は `DOTFILES_USER` 未指定時に `nixos` を使う。WSL postinstall は `--user` で選択した
ユーザーの `DOTFILES_USER` / `DOTFILES_HOME` / `DOTFILES_UID` / `DOTFILES_GID` /
`DOTFILES_GROUP` を export し、`nixos-rebuild` を `--impure` 付きで実行する。これにより
flake 評価中の `builtins.getEnv` が選択した識別情報を読み取り、NixOS host、Home Manager、
`wsl.defaultUser` の対象を一致させる。
`nrs` / `nrt` / `nrb` は `scripts/sh/nixos-rebuild-with-user.sh` 経由で実行し、同じ識別情報を
flake 評価へ渡す。

## Home Manager 固有のチェック

- OS 固有設定は対象 OS の Home Manager ファイルに追加し、`common.nix` に OS 条件を増やさない。
- Nix option、package、session variable のテストは `nix/tests/unit/` に追加し、
  全 system の flake 評価と対象 system の `nix-unit` build を実行する。
- Bats は Home Manager option の値を検査する用途には使わず、installer、shell、外部プロセス、
  runtime 契約に限る。`tests/bash/package_catalog.bats` の値テストは移管済みで、
  残る runtime / artifact 契約の分類は [Nix テスト](../tests/README.md) に記載する。
  `nixos_wsl_postinstall.bats` の `nix eval` は、stubbed `nixos-rebuild` 境界内で選択 user と
  `--impure` 伝播を実 Nix eval で確認する runtime/integration assertion に限る。新しい例外は追加しない。

ホストの system 設定は `nix/hosts/<host>/configuration.nix`、import の入口は同じディレクトリの
`default.nix` が所有します。Home Manager の OS 差分は `nix/home/<os>.nix` に置き、host
configuration と混在させません。
