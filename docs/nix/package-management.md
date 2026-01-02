# パッケージ管理

## ユーザー単位 (Home Manager)

`nix/profiles/home/common.nix` の `home.packages` に追加します。

```nix
home.packages = with pkgs; [
  git
  ripgrep
  fd
];
```

反映:

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#myNixOS
```

## システム全体

`nix/modules/host/default.nix` の `environment.systemPackages` に追加します。

```nix
environment.systemPackages = with pkgs; [
  git
  curl
];
```

反映:

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles#myNixOS
```

## 注意点

- WSL では `flake.lock` が `~/.dotfiles` に作られます。
- Windows 側で編集した場合は `.\install-nixos-wsl.ps1` で同期してから反映します。
