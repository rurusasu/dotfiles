# nix: 構成変更時の作業基準

## 役割

- NixOS/WSL のシステム構成
- flake-parts による出力定義
- `nix profile` 向け package set

## 編集先の目安

- ホスト固有: `nix/hosts/`
- 再利用モジュール: `nix/modules/`
- Home Manager: `nix/home/`
- パッケージ SSOT: `nix/packages/all.nix`
- flake wiring: `nix/flakes/`

## 実行

```bash
nix profile install .#default
sudo nixos-rebuild switch --flake .#nixos
```
