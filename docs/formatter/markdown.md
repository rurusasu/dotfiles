# Markdown フォーマット設定 (dprint)

[dprint](https://dprint.dev/) を使用して Markdown ファイルをフォーマットします。

## 設定ファイル

[.dprint.json](../../.dprint.json)

```json
{
  "$schema": "https://dprint.dev/schemas/v0.json",
  "lineWidth": 100,
  "markdown": {
    "lineWidth": 100,
    "textWrap": "maintain",
    "emphasisKind": "asterisks",
    "strongKind": "asterisks",
    "newLineKind": "lf"
  },
  "plugins": ["https://plugins.dprint.dev/markdown-0.17.8.wasm"]
}
```

## 設定オプション

| オプション     | 値            | 説明                                                  |
| -------------- | ------------- | ----------------------------------------------------- |
| `lineWidth`    | `100`         | 行の最大幅                                            |
| `textWrap`     | `"maintain"`  | テキストの折り返し方法。`maintain` は既存の改行を維持 |
| `emphasisKind` | `"asterisks"` | イタリックのマーカー。`*text*` を使用                 |
| `strongKind`   | `"asterisks"` | 太字のマーカー。`**text**` を使用                     |
| `newLineKind`  | `"lf"`        | 改行コード。Unix 形式 (LF) を使用                     |

## textWrap オプション

| 値           | 説明                                             |
| ------------ | ------------------------------------------------ |
| `"always"`   | 常に lineWidth で折り返す                        |
| `"never"`    | 折り返さない                                     |
| `"maintain"` | 既存の改行を維持（推奨：日本語ドキュメント向け） |

## emphasisKind / strongKind オプション

| 値              | イタリック | 太字       |
| --------------- | ---------- | ---------- |
| `"asterisks"`   | `*text*`   | `**text**` |
| `"underscores"` | `_text_`   | `__text__` |

## インストール

### Nix (推奨)

```bash
# nix profile (flakes)
nix profile install nixpkgs#dprint

# nix-env
nix-env -iA nixpkgs.dprint

# nix run (一時的)
nix run nixpkgs#dprint -- --help
```

### その他

```bash
# cargo
cargo install dprint

# winget (Windows)
winget install dprint.dprint

# npm
npm install -g dprint
```

## 使用方法

```bash
# 単体実行
dprint fmt "**/*.md"

# treefmt 経由
treefmt

# チェックのみ
dprint check "**/*.md"
```

## .treefmt.toml 設定

```toml
[formatter.dprint]
command = "dprint"
options = ["fmt"]
includes = ["*.md"]
```

## treefmt-nix 設定

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix) で設定:

```nix
{
  treefmt = {
    programs.dprint.enable = true;
  };
}
```

### treefmt-nix ソース

- [programs/dprint.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/dprint.nix)

### 利用可能なオプション

```nix
{
  programs.dprint = {
    enable = true;
    # パッケージを指定
    package = pkgs.dprint;
  };
}
```

## エディター設定

### VSCode / Cursor

拡張機能: [dprint](https://marketplace.visualstudio.com/items?itemName=dprint.dprint)

```json
{
  "[markdown]": {
    "editor.defaultFormatter": "dprint.dprint",
    "editor.formatOnSave": true,
    "editor.wordWrap": "on"
  }
}
```

### Zed

```json
{
  "languages": {
    "Markdown": {
      "formatter": {
        "external": {
          "command": "dprint",
          "arguments": ["fmt", "--stdin", "md"]
        }
      },
      "soft_wrap": "editor_width"
    }
  }
}
```

## 参考リンク

- [dprint 公式サイト](https://dprint.dev/)
- [treefmt-nix dprint 設定](https://github.com/numtide/treefmt-nix/blob/main/programs/dprint.nix)
- [Markdown プラグイン設定](https://dprint.dev/plugins/markdown/config/)
- [GitHub リポジトリ](https://github.com/dprint/dprint)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=dprint.dprint)
