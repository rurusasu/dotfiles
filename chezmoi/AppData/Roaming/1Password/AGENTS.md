# chezmoi/AppData/Roaming/1Password: Windows-side 1Password 設定

## 管理対象

- `ssh/agent.toml`: 1Password SSH エージェントの鍵フィルタ

## 役割

1Password 8 の SSH エージェントが offer する鍵を whitelist で絞り込み、
OpenSSH の `MaxAuthTries=6` 制約を超えないようにする。

## デプロイ先

`%APPDATA%\1Password\ssh\agent.toml`（= `~/AppData/Roaming/1Password/ssh/agent.toml`）

1Password 8 (Windows) はこのパスを起動時に読み込み、agent を再起動すると
反映される。

## ルール

- 各 `[[ssh-keys]]` の `item` は **item ID** で書く（rename 耐性 + 同名 item
  との曖昧さ回避）。
- `vault` と `account` も併記して `WHERE` 句的に絞り込み、誤マッチを防ぐ。
- `account` は sign-in address（例: `my.1password.com`）で書くと
  human-readable。UUID でも動作する。

## 関連

- LIF-184: 本 file 導入
- ssh/config.tmpl の `IdentityFile` で参照する公開鍵は item ID と
  対になっている（personal=signing_key.pub, work=github_work.pub）。
