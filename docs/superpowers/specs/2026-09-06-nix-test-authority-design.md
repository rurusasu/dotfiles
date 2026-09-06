# Nix 設定テスト責務統一 Design

## 目的

Nix 式、Home Manager module、OS 別 Home Manager composition、Nix package
selection の authoritative test layer を Nix に統一する。Bats は shell script、installer
の command ordering、外部プロセス境界など、Nix 式そのものではない契約に限定する。

## 根本原因

現在は次の二つの test authority が並立している。

1. `nix/tests/home/` の `nix-unit` は import path と source structure を検査する。
2. `tests/bash/flake_outputs.bats` と `tests/bash/macos_config.bats` は `nix eval` を呼び、Nix
   configuration の実効値を検査する。

さらに `nix/tests/home/README.md` は static test と configuration evaluation を説明上は
分けているが、Nix 設定の実効評価を Bats 側に残している。この分割が、Nix 設定変更時に
Bats へテストを追加する誘因になっている。

## テスト構成

### Nix-native tests

`nix/tests/` 以下に以下を置く。

- import/layout boundary: relative path と import direction の静的検査
- Home Manager composition: `home-manager.lib.homeManagerConfiguration` と test 用 pkgs を
  使った module 評価
- OS ownership: Darwin、native Linux、WSL それぞれの実効 option と package set の検査
- flake output/configuration: NixOS/WSL/Darwin の Nix config が提供する Nix option の検査

テストは `nix-unit` の attrset として `nix/flakes/tests.nix` から登録する。環境変数、secret、
network、activation、外部 command は使用しない。ユーザー名と home はテスト module で固定値を
与え、`builtins.getEnv` の実行環境依存を避ける。

### Bats tests

Bats に残すのは以下だけとする。

- shell helper の command/result contract
- installer の実行順序、retry、failure handling
- `nix`、`brew`、`docker` など外部 command の stub 境界
- 実機・OS runtime に依存する acceptance

Nix option、Home Manager module の package/session variable、flake output の値を直接検査する
ために Bats から `nix eval` を呼ぶテストは Nix-native suite へ移す。

## Home Manager module 責務

`nix/home/common.nix` は username/home discovery、stateVersion、共通 session variables、
共通 PATH、共通 zsh/program integration だけを持つ。

- `nix/home/darwin.nix`: Darwin package selection、coreutils/terminfo、Homebrew/1Password
  variables、Homebrew PATH、Darwin WezTerm terminfo workaround
- `nix/home/linux.nix`: native Linux package selection
- `nix/home/wsl.nix`: WSL package exclusion、WSL variables、fcitx5/keyring services、WSL aliases

`common.nix` は `isWSL` と `pkgs.stdenv.hostPlatform.isDarwin` による OS branch を持たない。

## ドキュメントと CI

- `nix/tests/home/README.md` に Nix-native test の authoritative command と範囲を記載する。
- `nix/README.md` と `nix/home/README.md` は Nix configuration の検証先として Bats を案内しない。
- CI routing は Nix test suite と Bats contract suite を別の責務として記録する。
- 静的な ownership check を追加し、Home Manager Nix-only test が `tests/bash/` に再導入されることを検知する。

## 完了条件

- Nix-native tests が common/Darwin/Linux/WSL の境界を評価している。
- `common.nix` に Darwin/WSL 固有設定が残っていない。
- Nix configuration 用の重複 Bats assertions が削除され、残存 Bats は明確な shell/installer/runtime 責務を持つ。
- README、AGENTS、CI ownership が同じルールを説明している。
- `nix flake check --all-systems`、format/lint、required GitHub Actions が成功する。
- PR review thread を解消し、repository の許可する merge 方式で `main` に merge される。
