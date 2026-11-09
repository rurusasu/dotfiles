# パッケージ管理

## 管理方針

Unix のアプリ本体は、共通の `nixpkgs` から取得することを原則とします。Home Manager で設定・連携も管理するアプリは標準の `programs.<name>.enable` と package 既定値を優先し、設定をユーザーが管理するアプリや標準 module のないアプリは `pkgs.<name>` を導入します。追加 flake や独自のダウンロード定義は、対象 OS の nixpkgs に同じアプリがない場合に限定します。

Linux / Darwin 共通の入力には `nixpkgs-unstable` を使い、検証する revision を `flake.lock` に固定します。
Darwin の標準依存まで利用するため、Linux 向けの `nixos-unstable` だけを基準にしません（[公式のチャネル選択](https://nix.dev/concepts/faq.html#rolling)）。
キャッシュがない revision では .NET SDK や Swift / LLDB の bootstrap に数時間かかる場合があります。
更新した lock は両 OS の producer build と E2E で検証してから反映します。

設定・package override・生成・連携を持つアプリは、導入と専用の実行依存も同じ module にまとめます。enable・単純な package list・単一代入だけなら module を作らず、`nix/defaults.nix` の必要な構成へ直接書きます。Home Manager 標準の package 既定値を優先します。

共通・OS 別構成はアプリ module の外で組み立てます。すべての実 module は `nix/modules/` 配下の `default.nix` を入口とし、`nix/discover-modules.nix` が再帰的に自動検出します。通常のディレクトリは Home Manager、`nixos/` / `darwin/` / `system/` 配下は NixOS / nix-darwin / 両 OS 共通の scope です。構成側には `programs.<name>.enable` などの型付き option だけを書き、アプリごとの import パス登録や公開一覧は作りません。統合・standalone Home Manager は同じ `home-manager.sharedModules` と自動検出入口を使います。

Hermes は同梱 Python を使い、プロジェクト依存は `uv` で管理します。`nix/defaults.nix` が uv を導入し、Python interpreter は直接 `home.packages` に追加しません。X API 同期の公開コマンドは `uv run --no-project --managed-python` を使い、Python の選択も uv に任せます。Nix 内部専用の Python 依存は各 module が管理します。

通常の CLI・GUI とユーザー設定は Home Manager が管理します。macOS の Obsidian / Raycast / Dia / 1Password もこの範囲です。OS 固有の設定・権限・システムサービス・連携は `nix/defaults.nix` の各 OS ブロックに置きます。専用の実行依存は、そのアプリやサービスの module が管理します。Neovim の補助 CLI・LSP・整形ツール・toolchain・プラグイン実行依存は `nix/modules/editors/nvim/` が所有します。

Windows の導入情報は `windows/winget/packages.json` を直接管理します。Unix の Nix module と独立した正本で、Nix から生成しません。通常の Windows セットアップは WinGet から GUI アプリを導入します。

明示的な CLI 例外として、Windows PowerShell 用の Superfile (`spf`) も WinGet で導入します。
WSL の Superfile は Home Manager が導入・設定を管理します。
OpenCode (`opencode`) と TUIOS (`tuios`) は `nix/defaults.nix` の Home Manager package 宣言から WSL / Darwin に導入します。Pi coding agent (`pi`) は同じ platform で `programs.pi-coding-agent.enable = true` を指定し、自動検出される Pi module が設定を管理します。
nixpkgs の opencode 2.2.5 は bun 1.4.4 の libc filter で fixed-output hash が Linux と Darwin で変わるため、`nix/defaults.nix` で `--libc="*"` と単一 hash に補正しています。上流の修正が入ったら override を削除します（[NixOS/nixpkgs#582673](https://github.com/NixOS/nixpkgs/issues/582673)）。

フォントパッケージと fontconfig 設定の値は `nix/modules/fonts/settings.nix` の通常の関数に一度だけ定義します。`fonts/default.nix`、`fonts/nixos/default.nix`、`fonts/darwin/default.nix` を対応する scope で自動検出し、`nix/defaults.nix:systemDefaults` の `dotfiles.fonts.enable` で有効化します。NixOS / nix-darwin 統合時は各 OS がフォントを導入し、standalone Home Manager の配布と共通 fontconfig・Linux GTK 設定は Home Manager module が管理します。WSLg への配布と dconf service の登録は `defaults.nix` の WSL 設定が担当します。

WSL の Noto CJK の追加導入・フォールバック指定は行いません。WSLg の配布フォントも UDEV Gothic NF と絵文字に揃えます。

共通の `fonts.fontconfig.defaultFonts` は `monospace` / `sansSerif` / `serif` を `UDEV Gothic NF`、`emoji` を `Noto Color Emoji` に設定します。Darwin での既定フォント設定は fontconfig を使うアプリに適用され、macOS 標準 UI / CoreText の既定フォントは変更しません。

Neovim はユーザー指定の Nixvim Home Manager module で設定します。`nixvim` input は設定 framework として使い、`nixpkgs.useGlobalPackages = true` と `nixpkgs` の follows により、本体・プラグインは共通の nixpkgs から取得します。

## nixpkgs を使わない例外

固定中の nixpkgs に同じアプリがないものは、現在の取得元を使います。nixpkgs へ収録された場合は標準パッケージへ切り替えます。

| アプリ                                                        | 取得元と理由                                                                                                                                                                                  |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| dsh（macOS）                                                  | `llm-agents` の package。`pkgs.deepseek-harness` は Linux のみ対応するため。Linux では `pkgs.deepseek-harness` を使う。                                                                       |
| Orca IDE                                                      | `llm-agents` の package。`pkgs.orca` は GNOME のスクリーンリーダーで、別のアプリ。                                                                                                            |
| Hermes Agent / Desktop                                        | 公式 `hermes-agent` flake の package と Home Manager module。対応する nixpkgs package がないため。                                                                                            |
| Strata Desktop / Control（Linux x86_64・Apple Silicon macOS） | 公式 `Niko1221/Strata` の Linux AppImage / macOS app archive と Control archive。同じアプリが nixpkgs にないため。`strata-release` input の release metadata と asset の SHA-256 を固定する。 |
| Dia ブラウザー                                                | `dia` input の公式 DMG。`pkgs.dia` は図表エディターで、別のアプリ。                                                                                                                           |
| Chrome DevTools MCP                                           | `mcp-servers` flake の package。対応する nixpkgs package がないため。                                                                                                                         |
| Docker MCP Gateway                                            | Docker 公式 Git source と同梱依存を `buildGo126Module` で構築。対応する nixpkgs package がなく、`pkgs.mcp-gateway` は別製品のため。Git revision と内容を input で固定する。                   |
| xurl                                                          | `xurl` input の upstream source を `buildGoModule` で構築。対応する nixpkgs package がないため。                                                                                              |
| Lifelog（WSL x86_64）                                         | 非公開 repository の公開済み Release tag をローカル checkout から取得し、`Cargo.lock` に従って Nix で構築。nixpkgs に同じアプリがないため。                                                   |
| Herdr TUI                                                     | ユーザー指定により、nixpkgs の package から公式の Nix インストール手順が案内する release flake へ切り替える。`herdr` input の安定版 tag と upstream の build toolchain を lock する。         |
| Steam（macOS）                                                | Homebrew cask。対象 OS 用の同じ GUI アプリを nixpkgs から導入できないため。                                                                                                                   |

ChatGPT は `pkgs.chatgpt` を使います。同梱 Codex CLI を使う設定も、この nixpkgs package 内のバイナリーを参照します。`hermes-xapi` はリポジトリ内の連携スクリプトです。

Google Drive は Windows では WinGet の `Google.GoogleDrive`、macOS では `google-drive` cask で公式 Drive for desktop を導入します。macOS の nixpkgs に同じ公式アプリがなく、システム連携を含む公式 installer が必要なため、Homebrew を使う例外です。Linux / WSL 向けの公式デスクトップ版は提供されていません（[公式の対応 OS](https://support.google.com/drive/answer/2375082)）。NixOS・standalone Linux・WSL は標準の `programs.rclone.enable` で nixpkgs の rclone を導入します。`rclone config` で Google Drive の認証を設定すると、ファイル操作や `rclone mount` を利用できます。Google アカウントの認証と接続先は利用者が設定し、自動同期・マウントは初期状態では有効にしません（[rclone の Google Drive 手順](https://rclone.org/drive/)）。

OS / Home Manager の反映より先に rclone をユーザープロファイルへ導入した場合、反映後は `nix profile remove rclone` でその entry を外し、宣言側からの更新に統一してください。

### Meta AI Assistant / Muse

指定された [Meta AI Assistant](https://ai.meta.com/meta-ai/assistant/) の[公式デスクトップ配布](https://ai.meta.com/meta-ai/download/)は macOS 向けです。Meta の Muse にも[別の公式ダウンロードページ](https://ai.meta.com/muse/download/)があり、デスクトップ版は macOS 向けです。どちらも Windows・Linux / WSL 向けのネイティブ版は案内されていません。nixpkgs の `muse` は音楽シーケンサー、`muse-code` はコーディング用 CLI であり、対象とは異なります。

2026-11-08 時点で [Homebrew の `muse` cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/m/muse.rb) は、署名付きダウンロード URL が必要なため無効化されています。公式の取得先 `https://muse.ai/api/hatch/app-download/mac` も、この環境からは `403` / `not_eligible` を返しました。このため自動インストールの宣言は追加していません。macOS では公式ページで利用資格を確認してインストーラーを取得し、公式の手順で導入してください。公開された固定可能な配布物、または有効なパッケージが提供された時点で宣言的な導入へ切り替えます。

### 共通テーマとフォント

`nix/defaults.nix` の共通 Home Manager 設定が `catppuccin.flavor = "mocha"` を宣言します。公式 `catppuccin/nix` input の Home Manager module を使い、導入済みアプリの port だけを有効にします。Ghostty・Neovim・bat はこの共通設定からテーマを生成し、superfile は共通 flavor を参照します。Herdr は `theme.name = "terminal"` で外側のターミナルの配色を引き継ぎます。macOS 自体の外観は Dark、Linux GTK のテーマも同じ flavor です。

フォント名は `fonts.fontconfig.defaultFonts`、共通サイズは `gtk.font.size` を正本として `nix/modules/fonts/default.nix` が管理します。Ghostty はこれらを参照します。macOS では GTK は有効にせず、共通のサイズ設定だけを利用します。Herdr・Neovim などの TUI は外側のターミナルのフォントを使います。

Windows Terminal のフォント・サイズ・配色と superfile のテーマは `nix/home/appearance.nix` が公式 Catppuccin palette と同じ共通設定から生成します。`task keybindings:export` で `nix/home/appearance.json` を更新し、chezmoi が Nix を呼ばずに読み込みます。Windows のシステム UI フォントは変更しません。

### Herdr の設定

`nix/modules/terminals/herdr/default.nix` は[公式設定](https://herdr.dev/ja/tui/docs/configuration/)に従い、標準 `programs.herdr.settings` から生成します。対話シェルは Home Manager の Zsh、シェル起動モードは OS に従う `auto`、新しいペインの作業ディレクトリは `follow` です。worktree のルートは有効な gwq の `worktree.basedir`、未導入なら `config.home.homeDirectory + "/worktrees"` を使います。

リモートアタッチは `remote.manage_ssh_config = true` で既存 SSH 設定を取り込む一時設定を使います。接続先や SSH サーバーの公開は追加しません。通知は右下の Herdr トーストと通知音を有効にし、Linux の再生依存 `paplay` も module が導入します。Kitty graphics は有効ですが、実際の描画には外側のターミナルの対応が必要です。サイドバーは状態記号、ステータス欄は zoom・サーバー名・時刻を表示します。

### Lifelog（WSL）

Lifelog は非公開 repository のため、公開 dotfiles の flake input には含めません。WSL x86_64 では `programs.lifelog.sourceDirectory` に checkout を用意し、GitHub の公開済み最新 Release を選択します。既定値は `config.programs.ghq.root + "/github.com/" + config.programs.git.settings.user.name + "/lifelog-core"` です。Git の `user.name` を repository の所有者名として使います。初回は GitHub CLI と Git の認証を済ませ、既定の配置に clone します。

```bash
repo="$(git config --get user.name)/lifelog-core"
checkout="$HOME/ghq/github.com/$repo"
gh repo clone "$repo" "$checkout"
```

`programs.ghq.root` や `programs.lifelog.sourceDirectory` を変更した場合は、その保存先を使ってください。

以下を Bash で実行して Release を選択し、設定を反映します。

```bash
repo="$(git config --get user.name)/lifelog-core"
checkout="$HOME/ghq/github.com/$repo"
tag=$(gh release view --repo "$repo" --json tagName --jq .tagName) &&
  [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] &&
  git -C "$checkout" fetch origin "refs/tags/$tag:refs/tags/$tag" &&
  printf '%s\n' "$tag" > "$checkout/.git/lifelog-release-tag" &&
  task --dir "$HOME/.dotfiles" nrs
```

Home Manager は指定 tag のコミット済みソースから Linux アプリをビルドし、`lifelog` コマンドとアプリメニューを導入します。checkout の作業中の変更や未リリースの `main` は含まれません。新しい Release を使うときは同じ手順を再実行します。GitHub の自動確認や定期更新は行いません。tag の記録がない環境や pure 評価では導入されず、公開 CI に非公開ソースは渡りません。`nrs` は `--impure` でローカルの tag を読みます。Nix store に展開されたソースはローカルの他ユーザーから読めるため、機密情報をソースに含めないでください。OCR は別途セットアップが必要です。

Docker MCP は `docker-mcp` input の公式リポジトリの既定ブランチから取得します。
Git revision と内容は `flake.lock` で固定し、`task update` で更新し、CI 検証後に `nrs` で反映します。
依存は source に同梱された `vendor/` を使い、ビルド中の追加ダウンロードは行いません。
ビルドには upstream の `go.mod` / `Dockerfile` と同じ Go 1.26 系の標準 `buildGo126Module` を使います。同梱 gRPC が Go 1.27 の HTTP/2 API 変更に未対応のためです。
Home Manager が単体の `docker-mcp` バイナリと利用サーバーの起動引数を反映します。Podman API を使い、Docker CLI の plugin link や profile sync は不要です。秘密情報は `task mcp:toolkit:secrets` で所有者だけが読み書きできるローカルファイルへ同期します。

Podman は標準の `services.podman.enable`、Lazydocker は `programs.lazydocker.enable` で導入します。Linux / WSL は rootless API ソケット、macOS は Home Manager の標準 Podman machine を使います。Lazydocker と MCP Gateway の wrapper は `DOCKER_HOST` の明示指定を優先し、未指定ならこの接続先を設定します。Docker CLI package は削除し、upstream が実行する `docker` コマンドだけを Podman へのリンクで供給します。Compose は `podman-compose` を provider とする `podman compose` を使います。既存の公開タスク `docker:prune` も Podman を対象にします。

NixOS / WSL の公開互換コマンドと API unit は標準の `virtualisation.podman.enable` / `dockerCompat` に任せ、Home Manager で重複定義しません。Home Manager の手書き API unit は standalone Linux に限定します。macOS / standalone の公開互換コマンドと、Lazydocker / MCP Gateway のパッケージ内の実行依存には共通の互換リンクを使います。

Ollama は共通 Home Manager の `services.ollama.enable` で標準 package とユーザーサービスを導入します。API は既定の `127.0.0.1:11434` で待ち受けます。モデルの自動取得や GPU backend の変更は行いません。`ollama pull <model>` で使用するモデルを選択します。

Strata は Linux x86_64 / WSLg と Apple Silicon macOS に `strata`（CLI）と `strata-desktop`（GUI）を導入します。[公式 release](https://github.com/Niko1221/Strata/releases) の latest feed (`releases/latest/download/strata-feed.json`) を input として使い、Desktop と Control は feed が示す同じ release の asset から取得します。`task update` で最新の安定版へ更新し、変更した lock を CI で検証します。共通の `update-flake-inputs.sh` が更新時に latest feed の版を解決し、同じ hash の版付き URL を確認して lock に保存します。input の original URL は latest のままなので、特定の版に固定し続ける設定ではありません。lock は feed の版付き URL・内容と asset の SHA-256 を固定するため、次の release 後も同じコミットを再現できます。`nix flake update` の単独実行では mutable URL が lock に残るため、更新には `task update` または `bash scripts/sh/update-flake-inputs.sh .` を使います。`nrs` / `./install.sh` は lock 済みの版を更新せず導入します。Desktop の製品版と Control の内部 build 番号は異なります。CLI は配布物に同梱された Python を使い、ユーザーディレクトリの別版 Control への自動引き継ぎは無効にします。Linux GUI も固定された Control を使います。macOS の `.app` は公式署名を保持するため変更せず、GUI は upstream の規則に従い、同梱版とユーザーが更新した Control の新しい方を使います。`STRATA_CONTROL_DIR` の指定だけでは新しいユーザー版への切り替えを禁止できません。モデルと推論エンジンは初回設定時に選び、ユーザーのデータディレクトリに取得します。

WSL の NVIDIA GPU は Windows 側のドライバーを使います。CLI・GUI の FHS 環境には `/usr/lib/wsl` を読み取り専用で公開し、同梱の `nvidia-smi` と CUDA driver library を参照します。Linux 用 NVIDIA ドライバーを WSL 内へ別途導入する必要はありません。
RTX 4060（VRAM 8GB）と約 48GB の RAM では、[Qwen3.6-35B-A3B](https://github.com/Niko1221/Strata/blob/main/docs/QWEN36.md) の `UD-Q4_K_XL`（約 22.9GB）を context 8K・並列数 1・画像なし・MTP draft なしで生成確認しています。VRAM に収まらない expert は CPU と RAM を使うため、モデル全体が GPU に載る構成ではありません。既定の Q8 decode 用追加コピーでは VRAM が不足したため、`STRATA_Q8_PACKED=0` で追加コピーを無効にします。MTP draft を無効にしても、このモデルの MTP block 自体はメモリに残ります。次のコマンドは CUDA engine とモデルを取得し、localhost:8080 で起動します。

```bash
strata launch --family qwen36 --model UD-Q4_K_XL --backend nvidia --gpu 0 \
  --context 8k --parallel 1 --vision off --access local \
  --set STRATA_Q8_PACKED=0 --set mtp=0 --set prefill=512 \
  --save-preset qwen36-local --yes --no-tui
```

以後は `strata launch --preset qwen36-local --no-tui` で起動し、`strata launch --status` で状態確認、`strata launch --stop` で停止します。

同じ RTX 4060 / 約 48GB RAM の WSL では、Qwen3.8-Flash-Next の `Q2_0` も GPU と CPU・RAM を併用して起動できます。初回取得は約 66.4GB で、約 28.8GB の検索テーブルは SSD 上に置いて参照します。context 8K・並列数 1・画像と drafting なしで使い、`vram-reserve-mib=1024` で GPU メモリに余裕を残します。

```bash
strata launch --family qwen --model q2_0 --backend nvidia --gpu 0 \
  --context 8k --parallel 1 --vision off --mtp off --drafting off \
  --set prefill=512 --set vram-reserve-mib=1024 --access local \
  --save-preset flash-next-local --yes --no-tui
```

Qwen3.6 と Flash-Next を切り替えるときは、`strata launch --stop` で現在のモデルを停止してから `strata launch --preset qwen36-local --no-tui` または `strata launch --preset flash-next-local --no-tui` で起動します。どちらも localhost:8080 を使います。

Core Ultra 7 265K（WSL に20コアを公開）/ RTX 4060 の drafting なしでの校正では、CPU ワーカー18を12・9・4に減らす設定と expert cache の更新頻度を上げる設定は改善せず、既定値を維持しました。PCIe 配分 `0.10` と `spec-min-p=0.30` の組み合わせは、校正用の3組の確認測定で約5%改善しました。

2026-11-07、engine 0.1.57、同じ Q2_0・context 8K・並列数1で、API へ同じ入力を各3回送った測定値は次のとおりです。速度は API が返すエンジンの `timings` の中央値で、長文入力は毎回4,869トークンを新規に処理しています。コード生成は192トークンで打ち切った速度比較で、完成したコードの正しさを評価したものではありません。長文からの情報抽出は全条件で3回とも正答しました。

| 測定         | drafting なし |         MTP |     DFlash2 |
| ------------ | ------------: | ----------: | ----------: |
| 日本語生成   |    39.1 tok/s |  37.8 tok/s |  34.3 tok/s |
| コード生成   |    38.7 tok/s |  51.8 tok/s |  56.2 tok/s |
| 長文入力処理 |   334.2 tok/s | 328.7 tok/s | 334.3 tok/s |

普段用は MTP の `flash-next-tuned`、コード優先用は DFlash2 の `flash-next-coding` として保存しています。どちらも `prefill=512`・`pcie-frac=0.10`・GPU メモリ予約1536MiBで使います。`prefill=auto` も起動しましたが、GPU の空きが約532MiBまで減ったため採用しませんでした。

MTP の補助層が未取得の場合、既存モデルの `--mtp on` 指定だけでは取得されないことがあるため、先に公式 installer で約5.21GBのテンソルを取得・変換します。

```bash
strata launch --stop
strata install -- --family qwen --model Q2_0 --context 8192 --parallel 1 \
  --vision no --mtp on --gpu 0 --yes --no-start
strata launch --preset flash-next-local --mtp on --drafting mtp \
  --set prefill=512 --set pcie-frac=0.10 --set vram-reserve-mib=1536 \
  --save-preset flash-next-tuned --yes --no-tui
```

以後は `strata launch --preset flash-next-tuned --no-tui` で起動できます。モデルや preset を切り替える場合は先に `strata launch --stop` で停止するか、起動時に `--restart` を指定します。

DFlash2 の追加取得は約1.2GBです。日本語の会話も速くなる設定ではないため、用途に応じて選びます。

```bash
strata launch --preset flash-next-local --drafting dflash2 --mtp off \
  --set pcie-frac=0.10 --set vram-reserve-mib=1536 \
  --save-preset flash-next-coding --restart --yes --no-tui
```

Pi の coding engine として使う場合は、AGENTS.md とツール定義・会話履歴を収めるため `flash-next-coding` を32K context に拡張します。KV cache は int8、GPU 常駐分は4096トークンに制限します。上記の速度比較は8Kで測定した値です。

```bash
strata launch --preset flash-next-coding --context 32k --kv int8 \
  --set kv-resident=4096 --save-preset flash-next-coding \
  --restart --yes --no-tui
pi
```

Pi の既定 provider は `strata`、モデルは `qwen3.8-flash-next-q2_0`、接続先は `http://127.0.0.1:8080/v1` です。生成上限4096・thinking off・自動 compaction を設定しています。`~/.pi/agent/models.json` は Home Manager が生成するため、接続設定は `nix/modules/ai_agents/pi/default.nix` で管理します。既存セッションでは `/model` から Strata のモデルを選択できます。

DeepSeek-V4.1-Flash（`ist-das-2.25bpw`、約 274GB）を 64GB の Apple Silicon Mac で使う場合は、初回設定でモデルと Metal engine を選び、context 8192・`--dspark none`・`--vision off`・Speed は Faster（`--experts 5`、Full は 6）で運用します。
Speed はアプリが run config の `args` に書く値で、`strata profile set` では変更できません。
生成された run config（`~/.strata/data/native-instances/*.json`）は API key・ランダムな UUID・engine と pack の絶対パスを含むため、dotfiles には置きません。
再現に必要な値だけをここに残します。

速度は VRAM に載る expert の量で決まります。
エンジン停止から間を置かずに起動すると他プロセスのメモリが残り、share が 21.3GB まで下がって CPU lane が expert の約半分になり、1 t/s 前後まで落ちます。
停止後は 3 分待つか OS を再起動してから起動してください。
Full に戻すときはアプリの Speed を Full にします。

| VRAM expert share | CPU lane | 生成速度（6.2K prompt・512 tok） |
| ----------------- | -------- | -------------------------------- |
| 26.8GB            | 2〜3%    | 5.9 t/s                          |
| 21.3〜21.6GB      | 約50%    | 0.85〜1.0 t/s                    |

Qwen3.8-Flash-Next を 64GB の Apple Silicon Mac で動かす場合は、[公式 Mac 手順](https://github.com/Niko1221/Strata/blob/main/docs/MAC.md) の推奨に従い Q2_0 と並列数 1 を選びます。次のコマンドは Metal エンジンとモデルを取得し、32K context の preset を保存して localhost:8080 で起動します。初回取得には画像対応と MTP を含め約 72.5GB の通信が必要です。以後は `strata launch --preset qwen-local --no-tui` で起動し、`strata launch --stop` で停止できます。

```bash
strata launch --family qwen --model q2_0 --context 32k --parallel 1 \
  --access local --save-preset qwen-local --yes --no-tui
```

Neovim / Hermes の追加プラグインと formatter の入力は、アプリ本体とは別の依存です。source input は引き続き `flake.lock` で固定し、設定を持つ実 module は `default.nix` として自動検出します。

## 分割の理由と編集先

[NixOS 公式の Modularity](https://nixos.org/manual/nixos/stable/#sec-modularity) は、構成を複数の module に分け、共通設定を共有し、`imports` で組み立てる仕組みを説明しています。[Writing NixOS Modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules) では module が構成の一つの論理的な側面を扱うと説明しています。[Home Manager の構成例](https://nix-community.github.io/home-manager/usage/configuration.html) は `programs.<name>` によるアプリ管理と `home.packages` によるユーザープロファイルへの導入を示しています。

このリポジトリでは、設定・package override・生成・連携の責務をアプリ・機能単位でまとめます。単純な有効化・package list・単一代入は `nix/defaults.nix` に直接書きます。以下のパスはリポジトリの配置方針であり、公式資料が必須のディレクトリ構成を定めているわけではありません。

| 編集先                                         | 責務                                                                                          |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `nix/modules/<app>/default.nix`                | アプリの有効化・package 選択・設定・連携・専用の実行依存                                      |
| `nix/modules/editors/nvim/runtime/default.nix` | Neovim の補助 CLI・LSP・整形ツール・toolchain・プラグイン実行依存                             |
| `nix/modules/ai_agents/hermes/default.nix`     | 公式 Hermes Home Manager の root・Desktop・gateway 設定、外部 LCM plugin                      |
| `nix/modules/ai_agents/mcp/default.nix`        | Codex / root Hermes が使う共通 `programs.mcp.servers` 定義                                    |
| `nix/modules/browsers/dia/`                    | `inputs.dia` を使う package 定義と Home Manager への導入                                      |
| `nix/treefmt.nix`                              | formatter 設定と nixpkgs PowerShell 拡張機能の同梱 PSScriptAnalyzer の選択                    |
| `nix/defaults.nix`                             | OS 基盤設定、型付き option による有効化、単純な有効化・package 宣言、アカウント、GC、公開出力 |
| `nix/home/`                                    | 共通キー配置と Windows 向け外観 export                                                        |
| `nix/home/keybindings/`                        | 共通キー配置                                                                                  |
| `windows/winget/packages.json`                 | Windows GUI の標準 package ID・source・Scope                                                  |

Hermes の root・Desktop・gateway は公式 Home Manager module、named profile は Git 正本と公式 CLI で管理します。
外部 LCM は `extraPlugins` に追加します。操作は [Hermes](../hermes-agent/bootstrap.md) を参照してください。

OS 基盤設定、型付き option による有効化、公開構成は `nix/defaults.nix`、アプリの導入・設定・サービス・activation は `nix/modules/` に置きます。共通 OS / Home Manager 設定は一つの `systemDefaults`、OS 別の Home Manager enable option も同じ `sharedModules` に宣言し、末尾の構成登録で `specialArgs.platform` と CPU の `system` を指定します。`configurations` が公開構成、`systemDefaults` が共通の Lix・OS GC・Home Manager 接続を宣言します。GC 日時は各 OS ブロック、standalone GC は `systemDefaults.home-manager.sharedModules` に置きます。

統合・standalone Home Manager は同じ `systemDefaults.home-manager.sharedModules` を使います。CPU 別の wrapper は設けません。GUI も各 OS の構成が対応するアプリの enable option を選択します。Darwin のブラウザーは Dia、Linux / WSLg は Chrome を使います。WSL は Chrome / Spotify / Signal / Obsidian / 1Password GUI を Nix で導入し、デスクトップキーから WSLg で開きます。Windows の 1Password CLI / Git signer 連携は維持します。

Homebrew / nix-homebrew・Google Drive と Steam の cask・ユーザー PATH は `nix/defaults.nix` に宣言します。native NixOS の Hyprland は Linux ブロックが有効化し、単純な GUI package は `defaults.nix` の Home Manager 設定が導入します。WSL / standalone へ compositor を自動導入しません。Discord は Darwin / native Linux の Home Manager module が管理します。Windows / WSL 向けの Windows Discord アプリは導入しません。

[共通のキー割り当て](../chezmoi/omarchy.md) は `nix/home/keybindings/` に一度だけ定義し、host が OS 統合と有効化を担当します。共通データや純粋な設定生成関数は Home Manager module ではないため、`imports` に渡しません。

## パッケージの追加

enable・package list・単一代入だけなら `nix/defaults.nix` の必要な構成へ直接書きます。設定・連携・package override・生成処理を持つ場合は `nix/modules/<app>/default.nix` にまとめます。GitHub CLI の設定ファイルは引き続きユーザーが管理します。

```nix
# nix/defaults.nix の Home Manager 設定
home.packages = [ pkgs.gh ];
```

Home Manager のアプリ module は `nix/modules/<app>/default.nix` として置き、設定を `lib.mkIf config.programs.<name>.enable` などで条件付けます。構成側の `defaults.nix` には標準 `programs.<name>.enable` などの型付き option を書きます。この二点だけで読み込みと有効化を追加でき、import パスや公開 catalog の追記は不要です。標準 option がないアプリ・機能だけ独自の型付き option を定義し、同じ機能の enable alias は増やしません。

アプリ固有の OS module は `<app>/nixos/default.nix`、`<app>/darwin/default.nix`、両 OS 共通なら `<app>/system/default.nix` に置きます。scanner は通常ファイルの `default.nix` だけを対応する scope へ読み込み、`package.nix`・`settings.nix`・renderer などの通常の関数は読み込みません。Pi を含むすべての実 module が同じ規則を使います。Windows の導入は独立した `windows/winget/packages.json` に記述します。

## OS ごとの反映

通常は個別コマンドではなく one-command installer を再実行します。

```text
Windows:          task install
macOS:            ./install.sh
NixOS:            ./install.sh
Ubuntu / Debian:  ./install.sh
```

- Windows は `windows/winget/packages.json` を正本として winget で導入します。
- `task install` は既存の PowerShell と winget で Windows のパッケージを導入した後、NixOS-WSL の導入、lock 済みの NixOS/Home Manager の反映、Windows chezmoi の順に一度ずつ実行します。WSLg の対象 GUI は Nix 側で導入します。実行順序は `taskfiles/install/taskfile.yml` が管理します。`install.cmd` / `install.ps1` が PowerShell で WinGet master を1回適用し、Task の導入後は Taskfile の WSL・chezmoi へ進みます。WinGet の実行経路はこの1か所で、直接の `task install` も同じ入口を使います。`-Phase Winget` は master の import のみを実行します。WSL 基盤の有効化だけ UAC 昇格します。既存アプリや Startup shortcut は自動削除しません。
- Codex CLI はどの OS でも個別導入せず、各 OS 向け ChatGPT アプリ付属の CLI を使います。Windows の GUI profile は Microsoft Store のデスクトップアプリを対象とし、npm/pnpm パッケージを導入しません。
- macOS は nix-darwin が Home Manager と nix-homebrew formula/cask を同じ switch に含めます。
- 非 NixOS Linux（Ubuntu/Debian など）は standalone Home Manager が Podman API を含むユーザー環境を適用します。OS service は管理しません。
- NixOS は NixOS generation に Home Manager と system module を統合します。

アプリと OS 設定はこの OS 別構成を唯一の通常インストール入口とします。
`full`、`minimal`、カテゴリ別などの独立した Nix profile 用パッケージ集合は
公開しません。Tart の macOS guest も通常の `install.sh` を使います。
CI は OS configuration を build することで、その構成に含まれるアプリも検証します。
standalone Home Manager は上記の OS 統合を使えない環境向けに維持します。
キー設定は各アプリの Home Manager module が Nix 定義から直接生成します。Windows 向けの外観 JSON は `task keybindings:export` で更新します。Darwin custom package の出力は `nix/defaults.nix` に定義します。

macOS の `nrs` は nix-darwin を通じて Nix/Home Manager と宣言済み Homebrew package を反映します。通常の CLI と Neovim・Ghostty は Nix 側で管理します。Homebrew の設定と cask は `nix/defaults.nix` に宣言します。Nix パッケージの版は `flake.lock` に従います。

### macOS の権限エラー

Nix / Home Manager / Homebrew の適用で権限エラーが出た場合は、macOS の設定画面で
実行元の端末アプリに必要な「アプリ管理」または「フルディスクアクセス」を許可してください。
macOS が再起動を求めたら端末アプリを `⌘Q` で終了して開き直し、`./install.sh` を再実行します。
Homebrew の `zap` や設定ファイルの配置で停止した場合の詳細は
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md#フルディスクアクセス)を参照してください。

### macOS の旧 provider サポート終了

旧 Homebrew provider を検出し、Nix provider の検証後に uninstall する
一度限りの自動移行は終了しました。通常インストールは現行 module の
導入定義を反映します。個別の移行処理ではなく、以下の宣言外パッケージの
クリーンアップを適用します。
旧 provider の metadata、移行処理、互換コマンドは提供しません。

### 自動クリーンアップ

- Nix の GC は定期的に、`--delete-old` 付きで実行します。各 profile の現行世代だけを残し、
  旧世代と未参照の store path を削除します。削除した世代へのロールバックはできません。
- nix-darwin / NixOS / NixOS-WSL はシステム側の GC、standalone Home Manager は
  標準のユーザー GC を使い、二重にスケジュールしません。
  実行間隔・削除オプション・Darwin の空き容量条件は `nix/defaults.nix:systemDefaults` に集約します。
- macOS は `homebrew.onActivation.cleanup = "zap"` により、設定反映時に生成 Brewfile にない
  Homebrew package を削除します。cask はその `zap` 定義に記載された設定・データも削除します。
  宣言から外す操作や module の無効化でデータを失う可能性があり、再インストールだけでは
  復元できません。手動インストールしたアプリや Mac App Store アプリは対象外です。
- この設定は任意のユーザーファイルやアプリのデータ全般を走査・削除するものではありません。

Dock の固定アプリと順序は `nix/modules/dock/default.nix` が管理します。
macOS 27 の標準「アプリ」（`/System/Applications/Apps.app`）を先頭に置き、
Nix package の ChatGPT・Dia・Ghostty・Obsidian の順に固定します。
追加の固定フォルダーと最近使ったアプリは表示しません。
Finder・ゴミ箱・起動中のアプリの表示は固定アプリの一覧とは別です。

通常インストールは Nix のビルド・activation、ユーザー設定の反映、環境の動作確認を行います。
application identity、署名、CLI version を独自の期待値と比較する provider 検証は廃止しました。
flake inputs の更新は `task update`（共通の `update-flake-inputs.sh`）を使い、取得内容は `flake.lock` で固定します。Dia は公式 appcast から最新版の版付き DMG URL を先に解決してから取得するため、更新ごとの DMG 二重取得を避けます。Dia / Strata とも original の latest URL を保持し、通常更新では最新版に追従します。更新と検証が完了した場合だけ lock を置き換えます。

非 NixOS Linux も `./install.sh` が通常の入口です。Home Manager の適用に追加の opt-in は不要です。

macOS で Homebrew cask の適用に失敗する場合は、
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md)
を参照してください。

## ComfyUI

`nix/defaults.nix` が標準 `pkgs.comfyui` を Unix 共通で導入します。
`comfyui` で起動し、ブラウザーで `http://127.0.0.1:8188` を開きます。
更新は `task update` と通常の Nix 設定反映で行います。

過去の macOS Desktop 版で Nix 出力の削除に失敗する場合は、
[旧 Comfy Desktop 出力の復旧手順](./homebrew-cask-troubleshooting.md#旧-comfy-desktop-の-nix-出力)を参照してください。

## Windows manifest

`windows/winget/packages.json` は WinGet 標準 import 形式の独立した正本です。source、package ID、必要な `Scope` を直接編集し、Unix module に Windows metadata を置きません。

`install.cmd` は `winget import --import-file windows/winget/packages.json --ignore-versions --accept-package-agreements --accept-source-agreements --disable-interactivity` を一度実行します。master に含む Task が利用できるようになってから、Taskfile の WSL → chezmoi へ進みます。NixOS の反映は WSL の処理で一回です。

WinGet と各アプリの installer が導入、更新、コマンドリンク、PATH 登録を管理します。独自のパッケージ別 JSON パース、PATH・リンク修復、検証 metadata はありません。import は共通の 3600 秒 timeout を使い、`DOTFILES_INSTALL_TIMEOUT_SECONDS` で変更できます。0 は timeout を無効にします。非ゼロ終了時は後続へ進みません。

Windows PowerShell で使う superfile・eza・fd・ripgrep・lazygit と、WSL の `git_status.windows_starship` 用 Starship・MinGit は Windows CLI の明示的な例外です。これらは標準の `Scope: user` を指定します。Windows の alias・関数は chezmoi、Unix のアプリと設定は Nix / Home Manager が管理します。PATH が更新された場合は新しい terminal / WSL セッションで確認します。

Chrome / Spotify / Signal / Obsidian の通常導入とキーからの起動先は NixOS-WSL です。Windows の 1Password は `op.exe` / Git signer 連携のため維持し、GUI の通常起動先は WSLg です。各 OS ではその OS のアプリに付属する CLI を使います。

Windows Dia は [公式サイト](https://www.diabrowser.com/)から手動導入します。master と独自 MSIX 導入処理からは削除しています。管理対象から外したアプリを自動 uninstall することはありません。

## システム package と Home Manager の境界

| 対象                                 | 管理先                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------- |
| shell / editor から使う Unix CLI     | アプリごとの Home Manager module。有効化だけの標準宣言は構成へ直接記載 |
| Linux / WSLg / Darwin の通常 GUI     | アプリごとの Home Manager module                                       |
| Neovim の LSP・整形ツール・toolchain | `nix/modules/editors/nvim/runtime/default.nix`                         |
| Podman API / machine、Lazydocker     | アプリごとの Home Manager module。NixOS 基盤は `nix/defaults.nix`      |
| macOS CLI                            | 原則 Nix/Home Manager、明示例外は Homebrew formula                     |
| macOS の例外 cask                    | `nix/defaults.nix`                                                     |
| Windows GUI/OS application           | `windows/winget/packages.json` と標準 winget import                    |
| shell、Git、terminal、editor 設定    | Unix は Home Manager、Windows は chezmoi                               |

同じ package を Home Manager と system layer の両方へ導入するのは、システムサービスや OS 統合が必要とする場合に限定します。Darwin の GitHub CLI は host 連携用に system package にも残します。通常の GUI を system package に置く理由にはしません。

dsh は `nix/defaults.nix` が導入します。Linux は `pkgs.deepseek-harness`、macOS は未対応のため `llm-agents` の package を使います。Google MCP は共通 Pipedream へ接続し、認証は [Google MCP](../hermes-agent/gmail-mcp.md) に従います。Codex の設定は Home Manager が管理し、NixOS / WSL は Linux アプリ付属 CLI、Windows は Windows アプリ付属 CLI を使います。

`nix/modules/ai_agents/chatgpt/` が ChatGPT アプリと同梱 Codex CLI の OS ごとの package 選択・導入・設定を管理します。WSL は Linux CLI のみを選び、GUI を導入しません。Windows の Store ID・導入情報は `windows/winget/packages.json` が所有します。

1Password CLI / GUI の導入と連携は `nix/modules/1password/` が管理します。通常の CLI / GUI は Home Manager が導入し、`ssh/default.nix` が公式 SSH agent socket の `IdentityAgent` / `SSH_AUTH_SOCK`、OS 別の Git 署名・WSL 連携は `nix/defaults.nix` に直接宣言します。WSLg GUI の起動先を変えても、Windows `op.exe` / signer 連携の認証方式は変更しません。

Git / ghq / gwq の導入・設定は `nix/modules/git/` にまとめます。`default.nix` は Home Manager 標準 `programs.git` の設定、`ghq/default.nix` は独自 option `programs.ghq.enable` / `programs.ghq.root` による導入と標準 `home.sessionVariables.GHQ_ROOT` への反映、既存の Git alias は Git 本体の module が管理します。ghq の保存先は全 OS 共通で `config.home.homeDirectory + "/ghq"` が既定値です。gwq も `programs.gwq.settings` から設定し、worktree の保存先は `config.home.homeDirectory + "/worktrees"` が既定値です。ユーザーパスは `config.home.homeDirectory` / `config.xdg.*` とアプリの option から生成し、ユーザー名やドライブ文字を固定しません。単純なパスの結合には Nix の `+` を使います。署名の OS 固有設定は `nix/defaults.nix` が管理します。全 OS の `nrs` alias は `task nrs` を呼び、Taskfile が Unix の `install.sh` と Windows の WSL rebuild を選びます。

lazygit は `nix/defaults.nix` の標準 `programs.lazygit.enable` で有効化し、Bash / Zsh の `lg` 連携は Home Manager の既定値を使います。Herdr は `nix/modules/terminals/herdr/` が設定を管理し、[公式の Nix 手順](https://herdr.dev/ja/tui/docs/install/#nix-でインストール) に従い、`herdr` input の安定版 release flake を `programs.herdr.package` に指定します。設定は標準 `programs.herdr.settings` から生成します。tag を更新するときは `flake.nix` の `inputs.herdr.url` を変更して `nix flake update herdr` を実行し、通常の OS / Home Manager 反映を行います。Windows 側には Herdr の installer や設定を配置しません。

Herdr の [公式設定方法](https://herdr.dev/ja/tui/docs/configuration/) に合わせ、`programs.herdr.mutableSettings = true` で通常の書き込み可能な `config.toml` を生成します。キーは `omarchy` input の公式 `config/herdr/config.toml` から `[keys]` を取得し、独自配列を持ちません。Nix はこの配列とシェル・worktree・外観・通知などの宣言値を管理し、未宣言の項目は Herdr の既定値を使います。`programs.herdr.settings` の宣言値は反映時に優先され、未宣言の設定はアプリの設定画面や通常のファイル編集で変更できます。Nix の宣言を削除しても、既に書き込み可能なファイルに残った値は自動削除されません。設定の確認は `herdr config check`、実行中サーバーへの再読み込みは `herdr server reload-config` を使います。公式既定値の一覧は `herdr --default-config` で確認できます。

OS 全体の反映に先行して Herdr だけを使う場合は、公式手順の `nix profile install github:herdrdev/herdr/v0.9.5` でユーザープロファイルへ導入できます。この entry は Home Manager の package より PATH 上で優先されるため、後で OS / Home Manager の反映が済んだら `nix profile remove herdr` で外し、以後は宣言された package から更新します。

エディタ固有の設定は `nix/modules/editors/` にまとめます。`nvim/` は Neovim 本体・設定・プラグインを所有し、`runtime/default.nix` が補助 CLI・LSP・整形ツール・toolchain とプラグインの実行依存を通常の PATH に導入します。これらを全エディタ共通の集約 module に移しません。運用は [Neovim](../chezmoi/neovim.md) を参照してください。

Orca AI IDE は macOS・Linux/WSL 共通の `nix/defaults.nix` の `home.packages` で `inputs.llm-agents.packages.${system}.orca` を導入します。導入だけのため、専用 module は作りません。バージョンは `flake.lock` の `llm-agents` input で固定します。GUI は `orca-ide`、CLI は `orca` で起動します。

zoxide / fzf / eza / bat / ripgrep / fd の導入・設定と zsh-patina の連携は `nix/modules/shells/plugins/` の各アプリ module に置きます。zoxide は標準連携の `--cmd cd` で `cd` / `cdi` を使い、WSL の除外ディレクトリは `nix/defaults.nix` の WSL ユーザー設定に置きます。fzf の Zsh は標準 integration の Ctrl+T/R・Alt+C を使い、検索コマンド・プレビューは `programs.fzf` の widget option に定義します。Unix の Bash integration は無効です。ripgrep の設定ファイルと `RIPGREP_CONFIG_PATH` は Home Manager が生成します。

zsh-patina 1.11.0 は無効な動的ハイライトでも照会を先に実行するため、module の nixpkgs package override で設定判定を照会より前へ移します。WSL の構文色分けと既存パスの識別を維持し、無効なコマンド判定によるファイル照会だけを省きます。Linux の `zsh-patina-disabled-lookups` check は両方の処理経路の照会回数と修正前後の色分けの同一性を実際の daemon で検証します。

Starship の有効化・Bash / Zsh の標準連携・プロンプトは `nix/modules/shells/plugins/starship/` にまとめ、`programs.starship.settings` から Home Manager が `~/.config/starship.toml` を生成します。

## 関連ファイル

- `nix/modules/`
- `nix/hosts/`
- `nix/defaults.nix:systemDefaults.home-manager.sharedModules`
- `nix/home/keybindings/`
- `nix/defaults.nix`
- `windows/winget/packages.json`
- `scripts/powershell/lib/Invoke-ExternalCommand.ps1`
