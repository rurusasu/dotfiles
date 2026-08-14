# Discord デスクトップアプリのクロスプラットフォーム導入設計

## 目的

既存の Nix catalog を SSOT として、dotfiles が対応する OS 全体へ Discord デスクトップアプリを宣言的に導入する。

対象は Windows、Apple Silicon macOS、NixOS、Ubuntu/Debian、その他 Linux。WSL は Windows 側の Discord を利用し、WSL 内へ別の GUI アプリは導入しない。

## 採用アプローチ

`nix/packages/sets.nix` に Discord の catalog entry を追加し、OS ごとの適切な provider を同じエントリから導出する。

| OS      | Provider                 | 実装上の扱い                                                 |
| ------- | ------------------------ | ------------------------------------------------------------ |
| Linux   | Nix `pkgs.discord`       | Home Manager の `home.packages` 経由で導入                   |
| macOS   | Homebrew cask `discord`  | nix-darwin の `homebrew.casks` 経由で導入                    |
| Windows | winget `Discord.Discord` | catalog から生成した manifest を PowerShell installer が適用 |

macOS では Nix package と Homebrew cask の二重導入を避けるため、catalog entry の `pkg` は Darwin で `null`、Linux で `pkgs.discord` とする。macOS の provider metadata は明示的に `homebrew-cask`、Linux は Nix の default provider とする。

Discord は GUI アプリであり、Windows manifest の `verifyCommand` は追加しない。既存の catalog 生成、provider coverage、macOS cask wiring を利用し、専用の installer logic は作らない。

## 変更範囲

- `nix/packages/sets.nix`
  - `desktop` category に Discord entry を追加
  - Nix package、winget ID、macOS cask provider を定義
- `windows/winget/packages.json`
  - `nix build .#winget-export` の出力から Discord entry を反映
- `tests/bash/package_catalog.bats`
  - Discord が Windows-only ではなく、winget と macOS cask を持つことを検証

設定配布、Discord のログイン、bot token、Hermes の Discord transport は本変更の対象外とする。

## 検証

次を実行して、宣言と生成物の整合性を確認する。

1. focused Bats test で catalog/provider metadata を検証
2. `nix fmt` と `git diff --check` で構文・空白を検証
3. `nix build .#winget-export` で Windows manifest を生成
4. `nix eval` で provider coverage と Linux/macOS の package/cask wiring を確認
5. 生成した manifest の差分を確認し、Discord が `Discord.Discord` として含まれることを確認

CI の live winget install や各 OS の GUI 起動確認は、この変更のローカル完了条件には含めない。provider metadata と生成物の検証を行い、実機での反映は各 OS の既存 installer/switch 実行時に行う。

## 完了条件

- 既存 catalog の provider coverage を壊さない
- Linux の Home Manager package set に Discord が含まれる
- Apple Silicon macOS の nix-darwin cask set に `discord` が含まれる
- Windows manifest に `Discord.Discord` が含まれる
- focused test、Nix formatter、manifest generation、差分チェックが成功する
