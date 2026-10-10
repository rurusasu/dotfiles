# install.cmd 実行後に Codex CLI が使えない場合

Codex CLI は ChatGPT アプリ付属のものを使います。dotfiles は npm から
`@openai/codex` をインストールせず、chezmoi で Codex の設定を配布します。

ChatGPT アプリの導入後、新しい PowerShell を開いて確認してください。

```powershell
Get-Command codex.exe -All
codex --version
```

CLI が見つからない場合は、ChatGPT アプリの CLI 連携と PATH を確認します。
