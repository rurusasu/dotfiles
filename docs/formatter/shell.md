# Shell フォーマット設定 (shfmt)

[shfmt](https://github.com/mvdan/shfmt) を使用して Shell スクリプトをフォーマットします。

## 概要

shfmt は Go 製の高速な Shell スクリプトフォーマッターです。Bash, POSIX sh, mksh をサポートしています。

## インストール

### Nix (推奨)

```bash
# nix profile (flakes)
nix profile install nixpkgs#shfmt

# nix-env
nix-env -iA nixpkgs.shfmt

# nix run (一時的)
nix run nixpkgs#shfmt -- --help
```

### その他

```bash
# Go
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# brew (macOS/Linux)
brew install shfmt

# apt (Debian/Ubuntu)
apt install shfmt
```

## 使用方法

```bash
# フォーマット（stdout に出力）
shfmt script.sh

# ファイルを上書き
shfmt -w script.sh

# 複数ファイル
shfmt -w *.sh

# チェックのみ
shfmt -d script.sh

# stdin から読み込み
cat script.sh | shfmt

# treefmt 経由
treefmt
```

## オプション

| オプション | 説明                       | デフォルト |
| ---------- | -------------------------- | ---------- |
| `-i N`     | インデント幅（0=タブ）     | 0 (タブ)   |
| `-bn`      | 二項演算子の後で改行       | false      |
| `-ci`      | case の後をインデント      | false      |
| `-sr`      | リダイレクトの前にスペース | false      |
| `-kp`      | カラム位置を保持           | false      |
| `-fn`      | 関数の開き括弧を次行に     | false      |

## .treefmt.toml 設定

```toml
[formatter.shfmt]
command = "shfmt"
options = ["-w"]
includes = ["*.sh"]
```

### カスタム設定例

```toml
[formatter.shfmt]
command = "shfmt"
options = ["-w", "-i", "2", "-ci"]
includes = ["*.sh", "*.bash"]
```

## treefmt-nix 設定

[nix/flakes/treefmt.nix](../../nix/flakes/treefmt.nix) で設定:

```nix
{
  treefmt = {
    programs.shfmt.enable = true;
  };
}
```

### treefmt-nix ソース

- [programs/shfmt.nix](https://github.com/numtide/treefmt-nix/blob/main/programs/shfmt.nix)

### 利用可能なオプション

```nix
{
  programs.shfmt = {
    enable = true;
    # インデント幅（デフォルト: 2）
    indent_size = 2;
  };
}
```

## .editorconfig 連携

shfmt は `.editorconfig` を参照します：

```ini
[*.sh]
indent_style = space
indent_size = 2
```

## エディター設定

### VSCode / Cursor

拡張機能: [shell-format](https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format)

```json
{
  "[shellscript]": {
    "editor.defaultFormatter": "foxundermoon.shell-format",
    "editor.formatOnSave": true
  },
  "shellformat.path": "shfmt"
}
```

### Zed

```json
{
  "languages": {
    "Shell Script": {
      "formatter": {
        "external": {
          "command": "shfmt",
          "arguments": ["-"]
        }
      }
    }
  }
}
```

## コード例

**Before:**

```bash
#!/bin/bash
if [ "$1" = "test" ];then
echo "Testing"
for i in 1 2 3;do
echo $i
done
fi
```

**After:**

```bash
#!/bin/bash
if [ "$1" = "test" ]; then
	echo "Testing"
	for i in 1 2 3; do
		echo $i
	done
fi
```

## シェル方言の指定

```bash
# Bash
shfmt -ln bash script.sh

# POSIX sh
shfmt -ln posix script.sh

# mksh
shfmt -ln mksh script.sh
```

## 参考リンク

- [shfmt GitHub](https://github.com/mvdan/shfmt)
- [treefmt-nix shfmt 設定](https://github.com/numtide/treefmt-nix/blob/main/programs/shfmt.nix)
- [EditorConfig](https://editorconfig.org/)
- [VSCode 拡張機能](https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format)
