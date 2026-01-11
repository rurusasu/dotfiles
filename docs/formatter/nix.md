# Nix フォーマット設定 (nixfmt)

[nixfmt](https://github.com/serokell/nixfmt) を使用して Nix ファイルをフォーマットします。

## 概要

nixfmt は Nix 言語の公式フォーマッターです。Nix 2.19 以降では `nix fmt` コマンドから直接利用可能です。

## インストール

```bash
# nix-env
nix-env -iA nixpkgs.nixfmt

# nix profile (flakes)
nix profile install nixpkgs#nixfmt

# nix run (一時的)
nix run nixpkgs#nixfmt -- file.nix
```

## 使用方法

```bash
# 単体実行
nixfmt file.nix

# 複数ファイル
nixfmt *.nix

# チェックのみ
nixfmt --check file.nix

# stdin から読み込み
cat file.nix | nixfmt

# treefmt 経由
treefmt
```

## treefmt.toml 設定

```toml
[formatter.nix]
command = "nixfmt"
includes = ["*.nix"]
```

## flake.nix での設定

```nix
{
  outputs = { self, nixpkgs }: {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
  };
}
```

これにより `nix fmt` コマンドが使用可能になります。

## エディター設定

### VSCode / Cursor

拡張機能: [Nix IDE](https://marketplace.visualstudio.com/items?itemName=jnoortheen.nix-ide)

```json
{
  "[nix]": {
    "editor.defaultFormatter": "jnoortheen.nix-ide",
    "editor.formatOnSave": true
  },
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nil",
  "nix.serverSettings": {
    "nil": {
      "formatting": {
        "command": ["nixfmt"]
      }
    }
  }
}
```

その他の Nix 関連拡張機能:

- [Nix Env Selector](https://marketplace.visualstudio.com/items?itemName=arrterian.nix-env-selector) - Nix 環境の選択
- [Alejandra](https://marketplace.visualstudio.com/items?itemName=kamadorueda.alejandra) - 別のフォーマッター

### Zed

```json
{
  "languages": {
    "Nix": {
      "formatter": {
        "external": {
          "command": "nixfmt",
          "arguments": []
        }
      }
    }
  }
}
```

## Language Server

Nix には複数の Language Server があります：

| Server | 特徴 |
|--------|------|
| [nil](https://github.com/oxalica/nil) | 高速、フォーマッター連携 |
| [rnix-lsp](https://github.com/nix-community/rnix-lsp) | 基本的な LSP 機能 |
| [nixd](https://github.com/nix-community/nixd) | 高機能、型推論 |

## nixfmt vs alejandra

| 項目 | nixfmt | alejandra |
|------|--------|-----------|
| 開発元 | Serokell | コミュニティ |
| スタイル | 公式 | 独自（opinionated） |
| 設定 | なし | なし |
| 速度 | 高速 | 高速 |

## コード例

**Before:**

```nix
{pkgs,...}:{environment.systemPackages=with pkgs;[vim git curl];services.nginx={enable=true;virtualHosts."example.com"={root="/var/www";};}}
```

**After:**

```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
  ];
  services.nginx = {
    enable = true;
    virtualHosts."example.com" = {
      root = "/var/www";
    };
  };
}
```

## 参考リンク

- [nixfmt GitHub](https://github.com/serokell/nixfmt)
- [Nix IDE 拡張機能](https://marketplace.visualstudio.com/items?itemName=jnoortheen.nix-ide)
- [nil Language Server](https://github.com/oxalica/nil)
- [Nix 公式ドキュメント](https://nixos.org/manual/nix/stable/)
