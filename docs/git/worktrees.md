# Git worktree の管理

worktree の作成・移動・一覧・削除には [gwq](https://github.com/d-kuro/gwq) を使う。
Unix CLI の導入、設定と Bash / Zsh の補完・移動連携は
`nix/modules/git/gwq/default.nix` が管理する。既存の `git gtr` も `gwq add` に転送する。

## Windows と WSL の共用

Git の `worktree.useRelativePaths = true` を次の場所で管理する。

| 環境                | 編集元                          | 反映先                                        |
| ------------------- | ------------------------------- | --------------------------------------------- |
| Linux / WSL / macOS | `nix/modules/git/default.nix`   | `~/.config/git/config`（Home Manager）        |
| Windows             | `chezmoi/dot_config/git/config` | `%USERPROFILE%/.config/git/config`（chezmoi） |

Git 2.48 以降が必要。Windows / WSL の両方で有効にしてから新しい worktree を作成する。
gwq の既定の保存先は、すべての Unix ホストでホーム配下の `worktrees` とする。
`worktree.auto_mkdir = true` により、保存先がなければ初回の `gwq add` で自動作成される。
Windows / WSL で共用するリポジトリは、worktree も同じ Windows ドライブ内に置く必要がある。
WSL 内のホームや別ドライブでは、相対リンクでも Windows と共用できない。
共用するときは、リポジトリを起点とする相対パスで作成先を指定する。
たとえばリポジトリ直下で `gwq add -b feature ../dotfiles-feature` とすれば、
ドライブ名を設定に固定せず、隣接するディレクトリに作成できる。
Herdr の既定の worktree 保存先も gwq と共有するため、Windows との共用時には同じ配置条件が必要になる。

設定の反映は WSL で `./install.sh`、Windows で `task chezmoi` を使う。
gwq の操作は WSL の Bash / Zsh で実行する。`gwq cd` は現在のシェルを移動する。

```sh
gwq list
gwq add -b codex/new-feature
gwq cd codex/new-feature
gwq remove --dry-run -b codex/completed-feature
gwq remove -b codex/completed-feature
```

## 既存リンクの一度きりの修復

設定を有効にしても既存の絶対パスは変わらない。
例えば Windows で記録された `D:/project/...` は、WSL の Git では相対パスとして解釈される。
実際のディレクトリが存在するのに、`gwq list` に不正なパスが表示される原因になる。

リポジトリと worktree の実際のパスを、実行環境で有効な形式で指定する。
WSL では次を実行する。スペースを含むパスは引数全体を引用する。

```sh
task --dir ~/.dotfiles worktree:repair \
  REPO=/mnt/d/lifelog \
  WORKTREE=/mnt/d/lifelog/.worktrees/self-introduction-slides
gwq list
```

Windows の Task から実行する場合は `REPO=D:/lifelog`、
`WORKTREE=D:/lifelog/.worktrees/self-introduction-slides` のように指定する。
このタスクは相対リンクへ修復し、コミット・ブランチ・未保存ファイルと配置先を保持する。
gwq に修復コマンドがないため、このタスクだけは Git の
`worktree repair --relative-paths` を実行する。通常の操作には gwq を使う。
すべてのリポジトリを rebuild 時に走査・変更する activation は設けない。

修復後に不要な worktree を削除する場合は、`gwq remove --dry-run -b <branch>` で
対象を確認してから `gwq remove -b <branch>` を実行する。
