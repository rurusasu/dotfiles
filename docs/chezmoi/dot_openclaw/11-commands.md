# Commands 設定

OpenClaw のコマンド登録・表示に関する設定セクション。

## 設定値一覧

| キー           | 値       | 説明                               |
| -------------- | -------- | ---------------------------------- |
| `native`       | `"auto"` | ネイティブコマンドの自動登録       |
| `nativeSkills` | `"auto"` | ネイティブスキルコマンドの自動登録 |
| `restart`      | `true`   | `/restart` コマンドの有効化        |
| `ownerDisplay` | `"raw"`  | オーナー情報の表示形式             |

## 設計判断

### auto モードによるコマンド登録

`native` と `nativeSkills` を `"auto"` に設定することで、OpenClaw がコマンド登録を自動管理する。手動でコマンドを列挙する必要がなく、新しいコマンドやスキルが追加された際にも設定変更なしで反映される。

### restart コマンドの有効化

`restart: true` により、チャット上から `/restart` コマンドで OpenClaw を再起動できる。設定変更後の反映やトラブル時の復旧に有用。

### ownerDisplay の raw 表示

`ownerDisplay: "raw"` は、オーナー情報をフォーマットせずそのまま表示する設定。デバッグや運用時に正確な値を確認する目的で採用している。

## リファレンス

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
