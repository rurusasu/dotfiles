# chezmoi/terminals/wezterm: WezTerm 設定

## 編集対象

- `wezterm.lua` は Windows 専用の設定。直接編集し、chezmoi で配布する
- macOS・NixOS・WSL の設定は `nix/modules/terminals/wezterm/defaults.nix` と `wezterm.lua` が管理する

## 変更ルール

- キーバインドは Windows Terminal と整合性を保つ。
- OS 分岐は `wezterm.target_triple` で管理する。
- 起動シェルや表示設定の変更は Windows/WSL 双方で確認する。
