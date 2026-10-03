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

- caller は共有する core module として対象 OS のファイルを import する。standalone 専用の
  責務は caller が個別 module を組み合わせる。standalone Darwin では `darwin.nix` に加え、
  font package と `$HOME/Library/Fonts` への activation を所有する `standalone-darwin-fonts.nix`
  を読み込む。共有する `darwin.nix` に standalone 専用の font activation を置かない。
- 各 OS ファイルは `./common.nix` を import する。
- `common.nix` から OS 固有ファイルを import しない。
- `default.nix` と `users.nix` は作らない。入口と OS 依存方向を曖昧にするため。

standalone Home Manager のユーザー名は `rurusasu` を既定値とする。Darwin のホームディレクトリは
`standalone-darwin-identity.nix` が実効ユーザー名から `/Users/<name>` を既定化し、明示指定で上書きできる。
Linux / WSL のホームディレクトリは各 OS ファイルが既定化する。nix-darwin / NixOS の
Home Manager submodule は host の `users.users.<name>.home` を使う。
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

ホストの system 設定は `nix/hosts/<host>/configuration.nix` と責務別 host module、import の入口は
同じディレクトリの `default.nix` が所有します。Darwin の system font は `fonts.nix`、OS-wide
defaults、timezone、defaults の反映 activation は `system.nix`、host identity、サービス、Homebrew、
統合固有の activation は `configuration.nix` に置きます。共有する Home Manager の OS 差分は
`nix/home/<os>.nix`、standalone 専用の責務は caller が組み合わせる個別 module に置きます。
