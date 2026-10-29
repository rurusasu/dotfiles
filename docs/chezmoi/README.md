# Chezmoi ドキュメント

chezmoi は Windows Terminal 設定と PowerShell 7 プロファイルを管理します。PowerShell 7 を既定プロファイルとし、NixOS-WSL は Windows Terminal が自動生成する `NixOS` プロファイルから起動します。

## 目次

- [インストールと適用](./usage.md)
- [ディレクトリ構造](./structure.md)
- [Nix と OS ごとの設定所有](../architecture.md)

## 所有境界

| 設定                                 | 所有者                                                |
| ------------------------------------ | ----------------------------------------------------- |
| Windows Terminal                     | chezmoi                                               |
| Windows PowerShell 7 profile         | chezmoi                                               |
| PowerShell 7 / Windows Terminal 本体 | [WinGet manifest](../../windows/winget/packages.json) |
| macOS、Linux、NixOS-WSL 内の WezTerm | Home Manager                                          |

PowerShell プロファイルは PSReadLine の履歴候補表示と共通エイリアスを設定します。詳しい適用方法は [usage.md](./usage.md) を参照してください。
