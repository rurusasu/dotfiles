# Home Manager レイアウト

`nix/home/` はユーザー単位の Home Manager 設定を管理します。OS 固有の入口は
`darwin.nix`、`linux.nix`、`wsl.nix`、共通設定は `common.nix` です。

## import の方向

依存方向は `caller -> <os>.nix -> common.nix` です。flake または NixOS/nix-darwin の
caller は対象 OS のファイルだけを読み込み、各 OS ファイルが `./common.nix` を import します。
`common.nix` から OS 固有ファイルを import してはいけません。

このため `default.nix` と `users.nix` は置きません。どちらも入口を曖昧にし、ユーザー別の
中継層を作って OS 固有の依存方向を逆転させるためです。ユーザー名とホームディレクトリは
`DOTFILES_USER` と `DOTFILES_HOME` から取り、NixOS の wiring では `DOTFILES_USER` 未指定時に
`nixos` を fallback とします。WSL では postinstall が同じユーザーを NixOS host と Home
Manager の両方へ渡すため、host 側の `wsl.defaultUser` と Home Manager の対象も一致します。
日常の `nrs`、`nrt`、`nrb` も `scripts/sh/nixos-rebuild-with-user.sh` を経由し、`sudo` 後の
flake 評価へ同じ識別情報を渡します。

## 所有境界

- `nix/hosts/`: system/host サービス、OS ユーザー、hardware 設定、host 固有の NixOS/nix-darwin
  設定を所有します。host/hardware 設定を `nix/home/` に置いてはいけません。
- `nix/packages/sets.nix`: クロスプラットフォームのパッケージ集合の単一情報源。Home Manager の
  `common.nix` はこの集合を消費します。
- `nix/home/`: Home Manager が所有するユーザー環境、ユーザー systemd サービス、OS 固有の
  Home Manager 設定。
- `chezmoi/`: Nix で表現しない dotfile、テンプレート、アプリケーション設定。Home Manager と
  chezmoi の両方で同じファイルを所有しないでください。

秘密情報はリポジトリやこのモジュールに直接書きません。既存の 1Password/chezmoi テンプレートや
実行時の環境変数を使い、秘密の値を Nix store に入れないでください。

## OS 固有設定を追加するチェックリスト

1. 対象 OS の `darwin.nix`、`linux.nix`、または `wsl.nix` に追加し、`common.nix` に OS 条件を
   増やさずに済むか確認する。
2. system/host サービス、ユーザー、hardware、host 固有設定なら `nix/hosts/` に追加し、
   `nix/home/` には置かない。
3. OS ファイルが `imports = [ ./common.nix ];` を維持し、`common.nix` が OS 固有ファイルを
   import しないことを確認する。
4. パッケージ追加なら先に `nix/packages/sets.nix` の所有範囲と各 OS への影響を確認する。
5. dotfile または秘密の扱いなら `chezmoi/` と既存の secret 経路に置き、所有の重複を避ける。
6. 対象 OS の評価と `nix flake check --no-build` を実行する。
