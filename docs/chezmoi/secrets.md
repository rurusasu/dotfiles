# シークレット管理

chezmoi でのシークレット（秘密情報）の管理方法。

## 概要

chezmoi は age または gpg を使って暗号化されたファイルを管理できます。

## セットアップ

### 1. 暗号化キーの準備

**age を使用する場合（推奨）:**

```bash
# age キーの生成
age-keygen -o ~/.config/chezmoi/key.txt
```

**gpg を使用する場合:**

```bash
# 既存の GPG キーを使用
gpg --list-keys
```

### 2. chezmoi 設定

`~/.config/chezmoi/chezmoi.toml` を作成:

**age の場合:**

```toml
encryption = "age"
[age]
  identity = "~/.config/chezmoi/key.txt"
  recipient = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

**gpg の場合:**

```toml
encryption = "gpg"
[gpg]
  recipient = "your-email@example.com"
```

## シークレットの追加

### 暗号化ファイルの追加

```bash
chezmoi add --encrypt ~/.ssh/id_rsa
chezmoi add --encrypt ~/.config/secret.json
```

これにより、ソースディレクトリに `encrypted_` プレフィックス付きのファイルが作成されます。

### テンプレートでのシークレット

`.tmpl` ファイル内で 1Password, Bitwarden, pass などからシークレットを取得できます:

```
# 1Password
{{ onepassword "item-name" }}

# Bitwarden
{{ bitwarden "item-name" }}

# pass
{{ pass "path/to/secret" }}
```

## ベストプラクティス

1. **暗号化キーをリポジトリにコミットしない**
2. **キーのバックアップを取る** - キーを紛失するとファイルを復号できなくなる
3. **`.gitignore` でキーファイルを除外**

## 確認

暗号化されたファイルの一覧:

```bash
chezmoi managed --include=encrypted
```

復号テスト:

```bash
chezmoi cat ~/.ssh/id_rsa
```
