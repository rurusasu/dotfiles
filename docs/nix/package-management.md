# パッケージ管理

## SSOT: `nix/packages/all.nix`

全プラットフォームのパッケージ定義を一元管理する Single Source of Truth。

```
nix/packages/all.nix
├── packages       → Home Manager で Linux/macOS にインストール
├── wingetMap      → nix attr → winget PackageIdentifier の対応表
└── windowsOnly    → Windows 専用アプリ (winget/msstore/pnpm)
```

## パッケージ追加

### クロスプラットフォームツール (Linux + Windows)

`nix/packages/all.nix` を編集:

```nix
# 1. packages のカテゴリに追加
core = with pkgs; [
  chezmoi
  git
  gh
  new-tool  # ← 追加
];

# 2. wingetMap に対応を追加
wingetMap = {
  new-tool = "Publisher.NewTool";  # ← 追加
};
```

### Linux 専用ツール

`packages` に追加するだけ。`wingetMap` への追加は不要。

### Windows 専用アプリ

`windowsOnly` セクションに追加:

```nix
windowsOnly = {
  winget = [
    "Publisher.NewApp"  # ← 追加
  ];
  msstore = [ ... ];
  pnpm = [ ... ];
};
```

## 反映手順

### Linux (WSL/NixOS)

```bash
sudo nixos-rebuild switch --flake ~/.dotfiles#nixos
```

### Windows (winget JSON 再生成)

```bash
# WSL 上で実行
nix build .#winget-export -o /tmp/winget-export
cp /tmp/winget-export/winget/packages.json /mnt/d/ruru/dotfiles/windows/winget/packages.json
cp /tmp/winget-export/pnpm/packages.json /mnt/d/ruru/dotfiles/windows/pnpm/packages.json

# Windows 上で反映
winget import -i windows/winget/packages.json --accept-package-agreements
```

## ファイル構成

| ファイル | 役割 |
| -------- | ---- |
| `nix/packages/all.nix` | SSOT: 全パッケージ + wingetMap + windowsOnly |
| `nix/home/packages.nix` | Home Manager module (`home.packages = allPkgs.packages`) |
| `nix/home/wsl/users.nix` | WSL ユーザーの Home Manager 設定 |
| `nix/packages/winget.nix` | `nix build .#winget-export` 用 derivation |
| `nix/packages/default.nix` | `nix profile install .#default` 用 package sets |
| `nix/modules/host/default.nix` | システムレベルのみ (nix settings, git, Docker) |

## Home Manager と systemPackages の使い分け

| 対象 | 管理先 |
| ---- | ------ |
| CLI ツール (git, ripgrep, neovim 等) | Home Manager (`nix/home/packages.nix`) |
| システム設定に必要なもの (git for nix flake) | `environment.systemPackages` |
| NixOS モジュール連携 (Docker, ZSH) | `nix/modules/host/default.nix` |

## CI による整合性チェック

`test-consistency.yml` が以下を検証:

1. `nix build .#winget-export` で winget JSON を生成
2. `windows/winget/packages.json` との diff をチェック
3. 差分があれば CI が失敗 → `nix build .#winget-export` の再実行を促す

## 注意点

- `windows/winget/packages.json` と `windows/pnpm/packages.json` は **生成ファイル**。直接編集しない
- WSL では `flake.lock` が `~/.dotfiles` に作られる
- `allowUnfree` は NixOS config (`nix/modules/host/default.nix`) で設定済み
- `nix profile install .#default` で使える package sets は `nix/packages/default.nix` で定義
