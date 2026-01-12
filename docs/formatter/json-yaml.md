# JSON/YAML フォーマット設定 (oxfmt)

[oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) を使用して JSON/YAML ファイルをフォーマットします。

## 設定ファイル

[.oxfmtrc.json](../../.oxfmtrc.json)

```json
{
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "semi": true,
  "singleQuote": false,
  "trailingComma": "es5",
  "bracketSpacing": true,
  "arrowParens": "always",
  "proseWrap": "preserve",
  "endOfLine": "lf"
}
```

## 設定オプション

| オプション       | 値          | 説明                               |
| ---------------- | ----------- | ---------------------------------- |
| `printWidth`     | `100`       | 行の最大幅                         |
| `tabWidth`       | `2`         | インデント幅                       |
| `useTabs`        | `false`     | スペースを使用                     |
| `semi`           | `true`      | セミコロンを追加                   |
| `singleQuote`    | `false`     | ダブルクォートを使用               |
| `trailingComma`  | `"es5"`     | ES5互換の末尾カンマ                |
| `bracketSpacing` | `true`      | オブジェクトリテラル内にスペース   |
| `arrowParens`    | `"always"`  | アロー関数の引数に常に括弧         |
| `proseWrap`      | `"preserve"`| 既存の改行を維持                   |
| `endOfLine`      | `"lf"`      | Unix形式の改行コード               |

## 対応フォーマット

oxfmt は以下のフォーマットに対応しています：

- JSON (`.json`)
- YAML (`.yaml`, `.yml`)
- JavaScript (`.js`, `.jsx`)
- TypeScript (`.ts`, `.tsx`)

## インストール

### Nix (推奨)

```bash
# nix profile (flakes)
nix profile install nixpkgs#oxfmt

# nix-env
nix-env -iA nixpkgs.oxfmt

# nix run (一時的)
nix run nixpkgs#oxfmt -- --help
```

### その他

```bash
# npm
npm install -g oxfmt

# cargo
cargo install oxfmt
```

## 使用方法

```bash
# 単体実行（書き込み）
oxfmt --write "**/*.json"

# チェックのみ
oxfmt "**/*.json"

# treefmt 経由
treefmt
```

## .treefmt.toml 設定

```toml
[formatter.oxfmt]
command = "oxfmt"
options = ["--write"]
includes = ["*.json", "*.yaml", "*.yml"]
```

## treefmt-nix 設定

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix) で設定:

```nix
{
  treefmt = {
    programs.oxfmt.enable = true;
  };
}
```

### treefmt-nix ソース

- Nix設定: [programs/oxfmt.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/oxfmt.nix)
- TOML例: [examples/formatter-oxfmt.toml](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-oxfmt.toml)

### 利用可能なオプション

```nix
{
  programs.oxfmt = {
    enable = true;
    # パッケージを指定
    package = pkgs.oxfmt;
  };
}
```

## JSON フォーマット例

**Before:**

```json
{"name":"example","version":"1.0.0","dependencies":{"lodash":"^4.17.21","express":"^4.18.2"}}
```

**After:**

```json
{
  "name": "example",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.21",
    "express": "^4.18.2"
  }
}
```

## YAML フォーマット例

**Before:**

```yaml
name: example
version: 1.0.0
dependencies: {lodash: ^4.17.21, express: ^4.18.2}
```

**After:**

```yaml
name: example
version: 1.0.0
dependencies:
  lodash: ^4.17.21
  express: ^4.18.2
```

## エディター設定

### VSCode / Cursor

拡張機能: [Oxc](https://marketplace.visualstudio.com/items?itemName=oxc.oxc-vscode)

```json
{
  "[json]": {
    "editor.defaultFormatter": "oxc.oxc-vscode",
    "editor.formatOnSave": true
  },
  "[yaml]": {
    "editor.defaultFormatter": "oxc.oxc-vscode",
    "editor.formatOnSave": true
  },
  "oxc.format.enable": true
}
```

### Zed

```json
{
  "languages": {
    "JSON": {
      "formatter": {
        "external": {
          "command": "oxfmt",
          "arguments": ["--stdin-filepath", "file.json"]
        }
      }
    }
  }
}
```

## 参考リンク

- [oxc 公式サイト](https://oxc.rs/)
- [treefmt-nix oxfmt (Nix)](https://github.com/numtide/treefmt-nix/blob/main/programs/oxfmt.nix)
- [treefmt-nix oxfmt (TOML例)](https://github.com/numtide/treefmt-nix/blob/main/examples/formatter-oxfmt.toml)
- [フォーマッター設定リファレンス](https://oxc.rs/docs/guide/usage/formatter/config-file-reference.html)
- [GitHub リポジトリ](https://github.com/oxc-project/oxc)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=oxc.oxc-vscode)
