# Neovim lazy.nvim Structured Setup 移行設計

## 目的

Neovim 設定を lazy.nvim 公式の Structured Setup に合わせる。lazy.nvim の bootstrap と `setup()` を `init.lua` から `lua/config/lazy.lua` へ分離し、起動処理の責務を明確にする。

## 対象範囲

- `chezmoi/dot_config/nvim/init.lua`
- `chezmoi/dot_config/nvim/lua/config/lazy.lua`

既存の `lua/plugins/init.lua`、`sidekick.lua`、`snacks.lua` はプラグイン仕様ファイルとして維持する。Windows の Python PATH 補正と通常の Neovim 基本設定も維持する。

## 構成

`init.lua` は次の責務に限定する。

1. Windows 上で Mason が実 Python を使うための PATH 補正
2. leader キーの設定
3. 基本設定モジュールの読み込み
4. `require("config.lazy")` による lazy.nvim 設定の読み込み

`lua/config/lazy.lua` は次を担当する。

1. `vim.fn.stdpath("data") .. "/lazy/lazy.nvim"` をインストール先として決定
2. lazy.nvim がなければ stable ブランチを shallow clone
3. clone の失敗を検出し、エラー内容を表示して終了
4. lazy.nvim を runtimepath の先頭へ追加
5. `plugins` 仕様を読み込み、既存の lazy.nvim オプションで setup

ファイル存在確認は `(vim.uv or vim.loop).fs_stat` を使い、Neovim の API 世代差に対応する。

## 起動順序

Windows PATH と leader キーを lazy.nvim より先に設定する。基本設定を読み込んだ後に `config.lazy` を読み込み、既存のプラグイン仕様と lazy-load 条件を変更しない。

## エラー処理

Git clone 後に `vim.v.shell_error` を確認する。失敗時は clone の出力を Neovim のエラー表示で通知し、壊れたインストール先を使って `require("lazy")` を続行しない。

## 検証

- Lua の構文チェックを実行する
- Neovim の headless 起動で設定がエラーなく読み込めることを確認する
- 最終 diff で `flake.lock` など対象外の既存変更を変更していないことを確認する
