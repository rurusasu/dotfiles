# Hermes Service Account Timeout and Cached Fallback

## Goal

`nrs` と `task hermes:bootstrap` が、ホストの 1Password CLI によるサービスアカウント取得待ちで無期限に停止しないようにする。

## Behavior

1. `op read` に既定 20 秒の上限を設ける。上限は
   `DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS` で正の整数に限り上書きできる。
2. 取得に成功したときだけ、既存どおり新しい `.op.env` を一時ファイル経由で `0600` として置き換える。
3. 取得が失敗またはタイムアウトしたときは、既存 `.op.env` が通常ファイル・非 symlink・`0600`・単一の非空
   `OP_SERVICE_ACCOUNT_TOKEN` 行である場合に限り、それを継続利用する。警告を標準エラーへ出す。
4. 有効なキャッシュがなければ失敗する。古い・不正なキャッシュを作成、修復、またはログ出力しない。

## Safety and Testing

- トークンは一切ログ、引数、Git に出力しない。
- Bats で、タイムアウト時の安全なキャッシュ利用、無効キャッシュの拒否、成功時の原子的な更新を検証する。
- Hermes の Bootstrap・Compose 再作成は、サービスアカウントが新規取得または安全にキャッシュ検証できた場合だけ実行する。
