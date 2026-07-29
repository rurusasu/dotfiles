# Homebrew cask のトラブルシューティング

## WezTerm nightly の `source_glob` エラー

### 対象

2026-07-29 時点の Homebrew 6.0.11 では、公式 `wezterm@nightly` cask の
`preflight_steps` が `source_glob` を使う一方、実行中の Homebrew がその引数を
正しく処理できず、インストールに失敗する場合があります。

代表的なエラー:

```text
Error: No such file or directory @ rb_file_s_rename -
(/opt/homebrew/Caskroom/wezterm@nightly/latest/{WezTerm-*,wezterm-*}/WezTerm.app, ...)
```

これは WezTerm の設定や配布 archive の破損ではなく、Homebrew 本体と
[公式 cask 定義](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/w/wezterm%40nightly.rb)
の一時的な互換性差です。

### 最初に試すこと

Homebrew を更新し、公式 cask をそのまま再試行します。

```zsh
brew update
brew install --cask wezterm@nightly
```

すでにインストール済みの場合:

```zsh
brew upgrade --cask --greedy wezterm@nightly
```

これで成功する場合、以下の暫定回避は不要です。

### 暫定回避

この手順は上記の `rb_file_s_rename` エラーが再現し、Homebrew の更新でも解消
しない場合だけ使用します。公式 tap の cask ファイルを一時編集するため、
インストール後に必ず復元してください。

1. 公式 cask tap をローカルに取得し、作業前に差分がないことを確認します。

   ```zsh
   brew tap --force homebrew/cask
   cask_tap="$(brew --repository homebrew/cask)"
   git -C "$cask_tap" diff --exit-code
   ```

   差分が表示された場合は、既存の変更を上書きせず作業を中止します。

2. cask 定義を開きます。

   ```zsh
   cask_file="$cask_tap/Casks/w/wezterm@nightly.rb"
   "${EDITOR:-vi}" "$cask_file"
   ```

3. `preflight_steps do` から対応する `end` までを、次の `preflight` block に
   一時的に置き換えます。

   ```ruby
   preflight do
     source_app = staged_path.glob("{WezTerm-*,wezterm-*}/WezTerm.app").first
     raise "WezTerm.app was not found in the staged archive" if source_app.nil?

     FileUtils.mv source_app, staged_path/"WezTerm.app"
   end
   ```

4. API版ではなく、編集したローカル cask 定義を使ってインストールします。

   ```zsh
   HOMEBREW_NO_AUTO_UPDATE=1 \
     HOMEBREW_NO_INSTALL_FROM_API=1 \
     brew install --cask wezterm@nightly
   ```

5. インストール結果を確認します。

   ```zsh
   brew list --cask --versions wezterm@nightly
   /opt/homebrew/bin/wezterm --version
   test -d /Applications/WezTerm.app
   ```

### 復元と後片付け

次の `git restore` は、上記手順で編集した cask 定義だけを公式状態へ戻します。
手順1で既存差分がないことを確認してから実行してください。

```zsh
git -C "$cask_tap" restore -- Casks/w/wezterm@nightly.rb
git -C "$cask_tap" diff --exit-code
brew untap homebrew/cask
```

一部の Homebrew バージョンでは、tap の削除完了後に `brew untap` が Git の
終了コードで失敗扱いになることがあります。その場合は、次のコマンドが何も
出力しなければ tap は削除済みです。

```zsh
brew tap | rg '^homebrew/cask$'
```

最後に、cask とバイナリが残っていることを再確認します。

```zsh
brew list --cask --versions wezterm@nightly
/opt/homebrew/bin/wezterm --version
```

### 終了条件

Homebrew 更新後に公式 cask を無編集でインストールまたは更新できるように
なった時点で、この暫定回避は使用しません。ローカル tap や変更済み cask
定義を恒久的に残さないでください。
