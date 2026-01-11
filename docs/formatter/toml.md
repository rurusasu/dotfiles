# TOML フォーマット設定 (taplo)

[taplo](https://taplo.tamasfe.dev/) を使用して TOML ファイルをフォーマットします。

## 設定ファイル

[.taplo.toml](../../.taplo.toml)

```toml
[formatting]
align_entries = false
array_trailing_comma = true
array_auto_expand = true
array_auto_collapse = false
compact_arrays = false
compact_inline_tables = false
column_width = 100
indent_tables = false
indent_entries = false
reorder_keys = false
allowed_blank_lines = 1
trailing_newline = true
```

## 設定オプション

### 基本設定

| オプション | 値 | 説明 |
|-----------|-----|------|
| `column_width` | `100` | 行の最大幅 |
| `trailing_newline` | `true` | ファイル末尾に改行を追加 |
| `allowed_blank_lines` | `1` | 連続する空行の最大数 |

### 配列設定

| オプション | 値 | 説明 |
|-----------|-----|------|
| `array_trailing_comma` | `true` | 配列の最後にカンマを追加 |
| `array_auto_expand` | `true` | 長い配列を複数行に展開 |
| `array_auto_collapse` | `false` | 短い配列を1行にまとめない |
| `compact_arrays` | `false` | 配列をコンパクトに表示しない |

### テーブル設定

| オプション | 値 | 説明 |
|-----------|-----|------|
| `align_entries` | `false` | エントリを揃えない |
| `indent_tables` | `false` | テーブルをインデントしない |
| `indent_entries` | `false` | エントリをインデントしない |
| `compact_inline_tables` | `false` | インラインテーブルをコンパクトにしない |
| `reorder_keys` | `false` | キーを並び替えない |

## インストール

```bash
# cargo
cargo install taplo-cli

# npm
npm install -g @taplo/cli

# winget (Windows)
winget install tamasfe.taplo
```

## 使用方法

```bash
# 単体実行
taplo format "**/*.toml"

# treefmt 経由
treefmt

# チェックのみ
taplo check "**/*.toml"

# lint（検証）
taplo lint "**/*.toml"
```

## treefmt.toml 設定

```toml
[formatter.taplo]
command = "taplo"
options = ["format"]
includes = ["*.toml"]
```

## スキーマサポート

taplo は TOML スキーマをサポートしています。`$schema` キーでスキーマを指定できます：

```toml
"$schema" = "https://json.schemastore.org/pyproject.json"

[project]
name = "my-project"
```

## エディター設定

### VSCode / Cursor

拡張機能: [Even Better TOML](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml)

```json
{
  "[toml]": {
    "editor.defaultFormatter": "tamasfe.even-better-toml",
    "editor.formatOnSave": true
  }
}
```

### Zed

```json
{
  "languages": {
    "TOML": {
      "formatter": {
        "external": {
          "command": "taplo",
          "arguments": ["format", "-"]
        }
      }
    }
  }
}
```

## 参考リンク

- [taplo 公式サイト](https://taplo.tamasfe.dev/)
- [設定リファレンス](https://taplo.tamasfe.dev/configuration/formatter-options.html)
- [GitHub リポジトリ](https://github.com/tamasfe/taplo)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml)
