# PowerShell 実装

- `install.ps1` は Windows の標準コマンドを実行し、順序は Taskfile が管理する。
- 共通処理は native 終了コード・timeout・文字コード・OS限定の昇格・プロセスPATHと、WSL登録・同期に絞る。
- クラス、結果オブジェクト、独自runner、テスト専用引数やラッパーは作らない。失敗は例外で伝える。
- distro登録は元のユーザーで実行し、基盤有効化のOSコマンドだけ昇格する。再起動要求は3010で停止する。
- WinGet、input更新、NixOS/Home Manager反映、chezmoi反映は各1回。
- テストは `tests/Invoke-Tests.ps1` を使い、現仕様の動作だけを確認する。
- 詳細は `docs/scripts/powershell/README.md`。
