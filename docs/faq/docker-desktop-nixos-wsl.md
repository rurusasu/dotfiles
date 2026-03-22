# Docker Desktop と NixOS-WSL の互換性問題

## 問題

Docker Desktop の WSL integration で NixOS を有効にすると、以下の問題が発生する:

1. **NixOS ディストリビューションが WSL から消える** — Docker Desktop が NixOS 内で proxy を実行しようとして失敗し、ディストリビューションの登録が破壊される
2. **Permission denied エラー** — `docker-desktop-user-distro proxy` が NixOS の read-only nix store にアクセスできない

### エラーメッセージ例

```
Docker Desktop - NixOS
WSL integration with distro 'NixOS' unexpectedly stopped.

running wslexec: An error occurred while running the command.
execvpe(/mnt/wsl/docker-desktop/docker-desktop-user-distro) failed: Permission denied
```

## 原因

NixOS-WSL はファイルシステムが Nix store（read-only）をベースにしており、Docker Desktop の WSL 統合が前提とする以下の操作と互換性がない:

- `/mnt/wsl/docker-desktop/docker-desktop-user-distro proxy` の実行
- `whoami` コマンドの直接呼び出し（NixOS の `$PATH` が無視される）
- Docker Desktop 4.45 以降で悪化（`whoami` を bash 経由ではなく直接呼ぶようになった）

## 解決策

### Docker Desktop の NixOS 統合をオフにする

1. Docker Desktop を開く
2. **Settings → Resources → WSL integration**
3. **NixOS のトグルをオフにする**
4. **Apply & restart**

### NixOS 内で Docker を使う方法

Docker Desktop の WSL 統合を使わずに、Docker ソケットを直接マウントする:

```nix
# nix/modules/host/default.nix
virtualisation.docker.enable = true;
```

または、Docker Desktop のソケットを NixOS 内からアクセスする:

```bash
export DOCKER_HOST=unix:///mnt/wsl/shared-docker/docker.sock
```

## 関連 Issue

- [nix-community/NixOS-WSL #235](https://github.com/nix-community/NixOS-WSL/issues/235) — nativeSystemd 有効時の Docker Desktop 統合失敗
- [docker/for-win #14931](https://github.com/docker/for-win/issues/14931) — Docker Desktop 4.45 で NixOS-WSL2 統合が壊れる
- [nix-community/NixOS-WSL #89](https://github.com/nix-community/NixOS-WSL/issues/89) — Docker Desktop WSL2 が NixOS で動作しない
- [nix-community/NixOS-WSL #50](https://github.com/nix-community/NixOS-WSL/issues/50) — ホスト Docker の利用方法の議論
- [docker/for-win #14979](https://github.com/docker/for-win/issues/14979) — WSL distro integration broken with Docker 4.50.0

## install.cmd への影響

- `Handler.Docker` は Docker Desktop の WSL 統合設定を変更しない（API が存在しないため）
- `Handler.WslConfig` は `wsl --terminate` を使用（`--shutdown` は Docker Desktop の WSL ディストリビューションを壊す可能性があるため廃止）
- NixOS ディストリビューションが消えた場合、install.cmd を再実行すれば `Handler.NixOSWSL` が自動的に再インストールする
