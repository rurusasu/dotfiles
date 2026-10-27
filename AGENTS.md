# dotfiles repository: 実装時の作業基準

## 最初に決めること

1. 変更対象が `nix/`, `chezmoi/`, `windows/`, `scripts/`, `docker/` のどれかを特定する。
2. パッケージ追加か設定変更かを切り分ける。
3. 反映先が macOS、Linux/WSL/NixOS、Windows のどれかを決める。

## 変更先の原則

- Unix のアプリ本体は原則として共通の `nixpkgs` から取得する。Home Manager で設定・連携も管理するアプリは標準の `programs.<name>.enable` と package 既定値を優先し、その他は `pkgs.<name>` を導入する。対象 OS の nixpkgs に同じアプリがない場合に限り、追加 flake や upstream 配布物を使い、理由を [パッケージ管理](docs/nix/package-management.md#nixpkgs-を使わない例外) に記載する。
- Unix のパッケージ導入とアプリ設定: `nix/modules/`。アプリごとの module が標準の `programs.*.enable`、package 選択、設定・連携、専用の実行依存をまとめて管理する。
- 設定・package override・生成・連携を持つアプリは module にまとめる。Neovim の LSP・整形ツール・toolchain・プラグイン実行依存は Neovim module が所有する。
- enable・単純な package list・単一代入だけの module は作らず、`nix/defaults.nix` の必要な構成へ直接書く。
- Hermes は同梱 Python を使う。Python interpreter を別途導入したり、直接 `home.packages` に追加したりしない。プロジェクト依存は uv で管理する。Nix 内部専用の Python 依存は各 module が管理する。
- すべての実アプリ module は `nix/modules/` 配下の `default.nix` として置き、自動検出させる。通常は Home Manager、`nixos/` / `darwin/` / `system/` ディレクトリ配下はそれぞれ NixOS / nix-darwin / 両 OS 共通の scope とし、`nix/discover-modules.nix` が対応する評価へ読み込む。アプリごとの import パス登録・公開一覧は作らない。有効化は `nix/defaults.nix:systemDefaults` の標準 `programs.<name>.enable` などの型付き option で選び、設定・package・service・activation を enable に従わせる。純粋な factory・renderer は通常の関数として利用し、`default.nix` を付けて自動検出させない。Windows のインストール情報は独立して管理する。詳細は [パッケージ管理](docs/nix/package-management.md#分割の理由と編集先)。
- Homebrew / nix-homebrew・cask・ユーザー PATH は `nix/defaults.nix` にまとめる。通常の CLI・GUI とユーザー設定は Home Manager が管理し、OS 固有の設定・権限・システムサービス・連携は `defaults.nix` の各 OS ブロックに置く。
- OS / Home Manager 設定は `nix/defaults.nix:systemDefaults` にまとめ、末尾の構成登録で `specialArgs.platform` と CPU の `system` を選択する。
- 共通の OS / Home Manager 設定は `nix/defaults.nix:systemDefaults` にまとめ、Home Manager 共通設定は同 module の `home-manager.sharedModules` に置く。OS 別ユーザー設定も同じ `sharedModules` 内で選択し、standalone と共有する。
- 共通キー配列は `nix/home/keybindings/bindings.nix`、各アプリの生成関数・設定は `nix/modules/`。OS 基盤設定と型付き option による有効化は `nix/defaults.nix` が担当する。純粋な設定生成関数を Home Manager module の imports に渡さない。
- Windows manifest: `windows/{winget,npm,pnpm}/packages.json`（直接管理する独立した正本。通常導入は WinGet の GUI のみ）
- アプリのユーザー設定・サービス・activation は `nix/modules/`、OS 基盤設定と型付き option による有効化は `nix/defaults.nix`、Windows は `chezmoi/` に置く。Unix の設定ファイルは標準 Home Manager option と `xdg.configFile` で管理し、二重配布しない。
- Windows 実行ロジック: `scripts/powershell/`
- CLI の実行順序・依存関係・公開コマンドは `Taskfile.yml` と `taskfiles/` に実装する。
- Bash/PowerShell は Taskfile から呼ばれる platform adapter、secret 処理、複雑な検証に限定し、CLI の処理順序を重複定義しない。

## テスト責務

- Nix expression、Home Manager option、flake output、Nix package 選択の値テストは `nix/tests/unit/` に nix-unit 形式で記載する。ビルド・実行テストの derivation は `nix/tests/build/`、共有入力は `nix/tests/fixtures/` に置く。
- `nix/tests/discover.nix` が `unit/**/*.nix` と `build/**/*.check.nix` を再帰的に自動検出し、`nix/tests/default.nix` が flake に接続する。個別テストの登録パス一覧は作らない。unit は `test...` 属性の集合、build は check 名をキーとする derivation の集合を返す。OS 条件による build ファイル単位の空集合は許可するが、空の unit ファイル・全体で 0 件・名前の重複は失敗させる。nix-unit も flake の `checks` 経由で実行する。`nix flake check --no-build` は評価確認であり、テスト実行の代わりにはならない。詳細は [Nix テスト](nix/tests/README.md)。
- テスト定義は共通 context の `fixtures` / `homeConfigurations` / `code` / `files` から必要な引数だけを受け取る。fixture・純粋な helper・asset を含め、リポジトリ内のファイルパスや import をテストへ書かない。`nix/tests/context.nix` と `source-tree.nix` が資源を自動索引し、手書きの公開 catalog や個別パス登録は作らない。Home Manager は `fixtures.mkHome` などと型付き option、helper は `code.*`、asset は `files.*` で参照する。
- Bats は shell、installer、外部コマンド、runtime/integration 契約に限定する。Nix option を `nix eval` するだけの Bats テストは追加しない。Windows manifest は CI で JSON を直接検証する。テストの分類は `nix/tests/README.md` に従う。WSL の初回同期は PowerShell ハンドラー、NixOS rebuild は直接コマンドを境界として検証する。

## フォーマット・テスト・実行時間の境界

- `task fmt` は formatter の書き換え、`task lint` は pre-commit の検査として分離する。`task commit` は先に `fmt` を実行するため、後続の `lint:no-format` では treefmt を再実行しない。
- formatter の対象外は構文が未展開時に成立しない chezmoi テンプレートなど、理由を `docs/formatter/AGENTS.md` と設定コメントに残せるものだけにする。対象外にしたファイルは展開後の semantic test で検証する。
- テスト runner は CI とローカルで共有し、テスト件数が 0 の実行を成功扱いにしない。skip は実行環境の境界として明示し、必要な契約を削除して時間を短縮しない。
- `CanApply` は判定専用で外部インストールやネットワークなどの副作用を持たせない。bootstrap は `Apply` に限定する。重複した preflight、同一 `nix eval`、同じ Docker build の再実行は、依存関係と成果物を保ったまま一度にまとめる。

## 実行コマンド

```bash
# dotfiles 反映（NixOS + Windows 両方）
dotf chezmoi        # task chezmoi の短縮形

# WSL/NixOS
nrs
sudo nixos-rebuild dry-build --flake ~/.dotfiles --impure
nix fmt
```

```powershell
# Windows
dotf chezmoi        # task chezmoi の短縮形
pwsh -File scripts/powershell/install.ps1
task test:powershell
task lint:all
```

## コミット前ルール

- worktree の作成・移動・一覧・削除は `gwq` を使う。Windows / WSL 共用では同じ Windows ドライブに置き、相対リンクを使う。既存リンクの修復だけは `task worktree:repair REPO=... WORKTREE=...` を使う（[運用手順](docs/git/worktrees.md)）。
- Windows から直接 `git commit` しない。
- `task commit -- "message"` を使う。
- 必要に応じて `pre-commit run --all-files` を実行する。

## PR / CI の SHA と報告

- CI 状態を確認・報告するときは、GitHub から PR の最新 head SHA をその場で取得する。会話履歴、ローカル HEAD、開いたままの Actions ページにある SHA を最新とみなさない。
- 各 workflow の検証対象は、そのイベントで受け取った head SHA に固定する。push 後は新しい head SHA の必須チェックを取り直し、以前の SHA の成功結果を新しい変更の検証として扱わない。
- PR の検証状況を書く場合は、完全な head SHA と、その SHA に対応する実際の Actions 結果を反映する。「実行中」「成功」は確認時点の状態に合わせ、失敗・未完了の必須チェックがあれば成功と表現しない。

## 参照先

- `docs/architecture.md`
- `docs/1password/README.md`（1Password / `op` 調査と OS 別運用）
- `docs/chezmoi/`
- `docs/taskfile/lint.md`
- `docs/git/commit.md`
