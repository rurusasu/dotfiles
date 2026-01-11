# JSON/YAML フォーマット設定 (oxfmt)

[oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) を使用して JSON/YAML ファイルをフォーマットします。

## 設定ファイル

[.oxfmtrc.json](../../.oxfmtrc.json)

```json
{
  "printWidth": 100
}
```

## 設定オプション

| オプション | 値 | 説明 |
|-----------|-----|------|
| `printWidth` | `100` | 行の最大幅 |

## 対応フォーマット

oxfmt は以下のフォーマットに対応しています：

- JSON (`.json`)
- YAML (`.yaml`, `.yml`)
- JavaScript (`.js`, `.jsx`)
- TypeScript (`.ts`, `.tsx`)

## インストール

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

## treefmt.toml 設定

```toml
[formatter.oxfmt]
command = "oxfmt"
options = ["--write"]
includes = ["*.json", "*.yaml", "*.yml"]
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

> **Note**: 現在は prettier を使用しています。oxfmt は CLI 経由で treefmt から実行されます。

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

> **Note**: 現在は prettier を使用しています。

## 参考リンク

- [oxc 公式サイト](https://oxc.rs/)
- [フォーマッター設定リファレンス](https://oxc.rs/docs/guide/usage/formatter/config-file-reference.html)
- [GitHub リポジトリ](https://github.com/oxc-project/oxc)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=oxc.oxc-vscode)
