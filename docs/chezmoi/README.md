# Chezmoi ドキュメント

chezmoi は Windows の WezTerm 設定と PowerShell 7 プロファイルを管理します。PowerShell は WinGet manifest から最新版を導入し、WezTerm の既定プロファイルとして起動します。NixOS-WSL は別の WezTerm プロファイルから起動します。

## 目次

- [インストールと適用](./usage.md)
- [ディレクトリ構造](./structure.md)
- [Nix と OS ごとの設定所有](../architecture.md)

## 所有境界

| 設定                                 | 所有者                                                |
| ------------------------------------ | ----------------------------------------------------- |
| Windows WezTerm                      | chezmoi                                               |
| Windows PowerShell 7 profile         | chezmoi                                               |
| Windows PowerShell / WezTerm package | [WinGet manifest](../../windows/winget/packages.json) |
| macOS、Linux、NixOS-WSL 内の WezTerm | Home Manager                                          |

PowerShell プロファイルは WezTerm 補完と PSReadLine の履歴候補表示を設定します。詳しい適用方法は [usage.md](./usage.md) を参照してください。
