# taskfiles 管理方針

- CLI の実行順序、依存関係、precondition、公開タスク名はここを正とする。
- 1 機能 1 ディレクトリ、ファイル名は必ず小文字の `taskfile.yml` とする。
- ルート `Taskfile.yml` は共有変数と include のみを管理し、実処理を重複定義しない。
- Bash/PowerShell は Taskfile から呼ぶ adapter とし、secret 処理や複雑な検証だけを担当させる。
- 既存の公開タスク名を変更せず、追加・移動後は `task --list` と関連テストで確認する。
- secret を Taskfile に直書きせず、破壊的な処理はタスク名と `desc` で明示する。
