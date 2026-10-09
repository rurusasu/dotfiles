# macOS の旧 oMLX の手動撤去

旧 Homebrew formula `jundot/omlx/omlx` と tap `jundot/omlx` の自動撤去は終了しました。
nix-darwin の通常 activation は旧 formula の uninstall や tap の削除を行いません。
未移行の端末では、所有者が利用状況を確認して一度だけ手動で撤去してください。

現在の構成ではローカル LLM サーバーを自動導入しません。旧サーバーのモデルや設定は通常 activation では移行・削除しません。

## 撤去前の確認

Homebrew を管理しているユーザーで実行します。

```bash
brew list --formula --versions omlx
brew tap
brew services list
command -v omlx
launchctl list | rg 'omlx'
```

oMLX のモデル・設定を保管し、利用しているクライアントの接続先を確認してください。
必要なクライアントの動作を確認してから旧 formula を撤去します。

## 一度だけ行う撤去

oMLX が不要になったことを確認した所有者が、次を実行します。
Homebrew service が登録されている場合は先に停止します。
手動起動している oMLX プロセスも、その起動方法で終了してください。

```bash
brew services stop omlx
brew uninstall --formula jundot/omlx/omlx
brew untap jundot/omlx
```

tap 内の別の formula を利用している場合は、`untap` を強制せずに残します。
最後に `brew list --formula --versions omlx` が未導入を示し、`brew tap` に
`jundot/omlx` が残っていないことを各対象端末で確認します。
リポジトリのテスト成功と、各端末での撤去完了は別に記録してください。
