# Lua フォーマット設定 (StyLua)

[StyLua](https://github.com/JohnnyMorganz/StyLua) を使用して Lua ファイルをフォーマットします。

## 設定ファイル

[.stylua.toml](../../.stylua.toml)

```toml
column_width = 120
indent_type = "Spaces"
indent_width = 4
```

## 設定オプション

| オプション     | 値         | 説明                       |
| -------------- | ---------- | -------------------------- |
| `column_width` | `120`      | 行の最大幅                 |
| `indent_type`  | `"Spaces"` | インデントにスペースを使用 |
| `indent_width` | `4`        | インデント幅（スペース数） |

## その他のオプション

| オプション                  | デフォルト           | 説明                                 |
| --------------------------- | -------------------- | ------------------------------------ |
| `line_endings`              | `"Unix"`             | 改行コード (`"Unix"` or `"Windows"`) |
| `quote_style`               | `"AutoPreferDouble"` | 文字列のクォートスタイル             |
| `call_parentheses`          | `"Always"`           | 関数呼び出しの括弧                   |
| `collapse_simple_statement` | `"Never"`            | シンプルな文を1行にまとめるか        |

## quote_style オプション

| 値                   | 説明                               |
| -------------------- | ---------------------------------- |
| `"AutoPreferDouble"` | ダブルクォートを優先（デフォルト） |
| `"AutoPreferSingle"` | シングルクォートを優先             |
| `"ForceDouble"`      | 常にダブルクォート                 |
| `"ForceSingle"`      | 常にシングルクォート               |

## インストール

### Nix (推奨)

```bash
# nix profile (flakes)
nix profile install nixpkgs#stylua

# nix-env
nix-env -iA nixpkgs.stylua

# nix run (一時的)
nix run nixpkgs#stylua -- --help
```

### その他

```bash
# cargo
cargo install stylua

# npm
npm install -g @johnnymorganz/stylua-bin

# winget (Windows)
winget install JohnnyMorganz.StyLua
```

## 使用方法

```bash
# 単体実行
stylua "**/*.lua"

# チェックのみ
stylua --check "**/*.lua"

# treefmt 経由
treefmt
```

## .treefmt.toml 設定

```toml
[formatter.stylua]
command = "stylua"
includes = ["*.lua"]
```

## treefmt-nix 設定

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix) で設定:

```nix
{
  treefmt = {
    programs.stylua.enable = true;
  };
}
```

### treefmt-nix ソース

- [programs/stylua.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/stylua.nix)

### 利用可能なオプション

```nix
{
  programs.stylua = {
    enable = true;
    # パッケージを指定
    package = pkgs.stylua;
  };
}
```

## コード例

**Before:**

```lua
local function hello(name) print("Hello, "..name.."!") end
local t={a=1,b=2,c=3}
```

**After:**

```lua
local function hello(name)
    print("Hello, " .. name .. "!")
end
local t = { a = 1, b = 2, c = 3 }
```

## エディター設定

### VSCode / Cursor

拡張機能: [StyLua](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua)

```json
{
  "[lua]": {
    "editor.defaultFormatter": "JohnnyMorganz.stylua",
    "editor.formatOnSave": true
  }
}
```

### Zed

```json
{
  "languages": {
    "Lua": {
      "formatter": {
        "external": {
          "command": "stylua",
          "arguments": ["-"]
        }
      }
    }
  }
}
```

## 参考リンク

- [StyLua GitHub](https://github.com/JohnnyMorganz/StyLua)
- [treefmt-nix stylua 設定](https://github.com/numtide/treefmt-nix/blob/main/programs/stylua.nix)
- [設定リファレンス](https://github.com/JohnnyMorganz/StyLua#configuration)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua)
