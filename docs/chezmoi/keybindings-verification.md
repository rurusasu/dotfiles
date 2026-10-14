# Omarchy キー配列の反映・確認記録

2026-10-14 の Windows / NixOS-WSL 環境での記録です。設定の配置、設定ファイルの検査、実際のキー入力を区別します。macOS / native NixOS の実機確認はこの記録に含みません。

## 反映対象

- 正本: `nix/home/keybindings/{bindings,ghostty,neovim}.nix`、WSLg transport は `ghostty-windows.nix`
- export: `nix/home/keybindings/generated.json`
- Windows: PowerToys Keyboard Manager の38割り当て、`Win+D` 無効化、Color Picker の有効化・起動キー、WSLg resize の8件の app-specific remap
- NixOS-WSL: Home Manager の loader と `~/.config/dotfiles/keybindings/` の Ghostty / Neovim export

「配置済み・未確認」は実キーでの動作をまだ確認していない意味です。定義やファイルの存在だけを実機での成功とは扱いません。

ブラウザと Spotify / Signal / Obsidian / 1Password GUI は WSLg 版へ起動先を変更し、実キーで起動 window を確認しました。旧 Windows 起動先で成功した観測は下に分離しています。アプリの認証・サービスへのログインは行っていません。起動直後は反映に遅延があり、後続 snapshot で window が現れたことを確認しています。

## Windows の実キー確認

| キー・操作                              | 状態                             | 観測・制約                                                                                                                                                                                         |
| --------------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Win+Enter`: Ghostty                    | 確認済み                         | NixOS-WSL の Ghostty が開いた                                                                                                                                                                      |
| `Win+Shift+B`: ブラウザ                 | 確認済み                         | WSLg Chrome window を確認                                                                                                                                                                          |
| `Win+Shift+Alt+B`: プライベートブラウザ | 確認済み                         | WSLg Chrome incognito window を確認                                                                                                                                                                |
| `Win+Shift+F`: ファイルマネージャー     | 確認済み                         | WSLg の Nautilus（Files）が開いた。再起動後も確認                                                                                                                                                  |
| `Win+Shift+T`: Btop                     | 確認済み                         | WSLg Ghostty の Btop window title を確認                                                                                                                                                           |
| `Win+Shift+M`: Spotify                  | 確認済み                         | WSLg Spotify window を確認。認証なし                                                                                                                                                               |
| `Win+Shift+/`: 1Password                | 確認済み                         | WSLg Welcome to 1Password window を確認。認証なし                                                                                                                                                  |
| `Win+Shift+N`: Neovim                   | 確認済み                         | WSLg Ghostty の Neovim window title を確認                                                                                                                                                         |
| `Win+Shift+C/E`: HEY Calendar / Email   | 確認済み                         | 実キーでそれぞれ別の WSL Chrome HEY login window を確認。ログインなし                                                                                                                              |
| `Win+Shift+A`: ChatGPT                  | 確認済み                         | 実キーで WSL Chrome の ChatGPT web window title を確認。ログインなし                                                                                                                               |
| `Win+Shift+G`: Signal                   | 確認済み                         | WSLg Signal window を確認。認証なし                                                                                                                                                                |
| `Win+Shift+Ctrl+G`: Google Messenger    | 確認済み                         | 実キーで WSL Chrome の「PC版Googleメッセージ」window を確認                                                                                                                                        |
| `Win+Shift+Alt+G`: WhatsApp             | 確認済み                         | 実キーで WSL Chrome の `web.whatsapp.com` window を確認                                                                                                                                            |
| `Win+Shift+D`: LazyDocker               | 確認済み                         | WSLg Ghostty の LazyDocker window title を確認                                                                                                                                                     |
| `Win+Shift+O`: Obsidian                 | 確認済み                         | WSLg Obsidian window を確認                                                                                                                                                                        |
| `Win+C/V`: コピー・ペースト             | 確認済み                         | Nautilus と Explorer のファイルコピー・貼り付け、Ghostty の選択文字 `nixos@nixos` の clipboard 完全一致・prompt への貼り付けを確認。Nautilus の日本語 fixture は内容の SHA256 も一致               |
| `Win+X/V`: カット・ペースト             | 一部確認済み                     | Nautilus と Explorer でファイルの移動を確認。Nautilus は移動元の消失と内容の SHA256 も一致。Ghostty の `Win+X` はコピー扱いとして実装されているが、実キーでは未確認                                |
| `Win+Ctrl+V`: 履歴                      | 初回画面を確認                   | Windows のクリップボード履歴を開いた。履歴が無効な場合の初回有効化はユーザー操作                                                                                                                   |
| `PrintScreen`: スクリーンショット編集   | 画像取得・保存・編集起動確認済み | ユーザーの範囲選択後、12:45:18 に PNG 保存と clipboard の1387×813画像を確認。Paint 起動修正後、正式 helper で同じ保存 PNG を開き、Paint の title・Canvas Size 1387×813px・File Size 113.7KB を確認 |
| `Shift+PrintScreen`: コピー             | overlay のみ確認                 | Snipping Tool の overlay は開いた。範囲選択がキャンセルされ、clipboard 画像は取得できず、撮影完了は未確認                                                                                          |
| `Alt+PrintScreen`: 録画                 | overlay 確認済み                 | 実キーで video icon が選択された標準録画 overlay と「図形を描画して記録領域を選択する」を確認。native `Win+Shift+R` を使用。Start や録画ファイル作成は未実施                                       |
| `Win+PrintScreen`: カラーピッカー       | 確認済み                         | PowerToys Color Picker overlay が開いた                                                                                                                                                            |
| `Alt+Shift+L`: URL 保存                 | 確認済み                         | WSL 全体の再起動後、実キーで通常 WSL Chrome の `https://example.com/` が Windows の `saved-urls.jsonl` に保存されたことを確認。クリップボード復元の実機確認は未実施                                |
| `Win+,`: 直近の通知削除                 | 確認済み                         | fixture 3件から最新 Tag3 が消え、所有する WinRT History は2件（Tag1/2）になった。13:29:09 の verified は `targetRemoved=true`。ログの `before=2, after=1` は UIA card 数で、実履歴件数とは別       |
| `Win+Shift+,`: 全通知削除               | 確認済み                         | 続けて実キーで削除し、所有する WinRT History が0件になった。13:29:29 の verified は `before=2, after=0, clearAllEnabled=false`。誤エラー判定も解消                                                 |
| `Win+Ctrl+,`: 応答不可                  | 確認済み                         | 11:16:16 に状態 `1→0`、11:16:38 に `0→1` の verified 記録。元に復元                                                                                                                                |
| `Win+Alt+,`: 通知履歴                   | 確認済み                         | 通知履歴が開いた                                                                                                                                                                                   |
| `Win+Ctrl+Shift+Space`: テーマ          | 確認済み                         | light/dark を切り替え、元の値 (`0/0`) に復元                                                                                                                                                       |
| `Win+Ctrl+Space`: 背景                  | 確認済み                         | 実キーで `TranscodedWallpaper` から Windows Spotlight `img14` への変更を確認。API で元の壁紙に復元                                                                                                 |
| `Win+Backspace`: 透明度                 | 確認済み                         | 前面ウィンドウで切り替え、元に復元                                                                                                                                                                 |
| `Win+Ctrl+I`: アイドル・スリープ抑止    | 確認済み                         | helper process の開始・終了を確認                                                                                                                                                                  |
| `Win+Ctrl+N`: 夜間モード                | 確認済み                         | UI Automation 修正後、11:12:07 に状態 `0→1`、11:12:41 に `1→0` の verified 記録。元に復元                                                                                                          |
| `Win+Shift+Space`: バー                 | 確認済み                         | タスクバーの自動非表示を切り替え、元に復元                                                                                                                                                         |
| `Win+Mute`: 音声出力                    | 1出力の判定確認済み              | computer-use が media key 非対応のため製品の native chord 送信で `Win+Mute` を入力し、他の出力がない旨の表示を確認。実 UI の1出力と一致。2出力以上の巡回は mock 検査のみ                           |
| `Win+D`: 無効化                         | 確認済み                         | デスクトップ表示への切り替えが起きなかった                                                                                                                                                         |

ブラウザの `Win+Shift+Enter` と Btop の `Win+Ctrl+T` は既存の別名として含みます。実キーでは未確認です。`Win+L` / `Ctrl+Alt+Del` などの Windows 予約操作は変更しません。

### 起動先変更前の観測

次は起動先が Windows 版だったときに、実キー入力で確認した記録です。WSLg アプリ・WSL Chrome の検証結果には含めません。

- ブラウザ: Windows Edge Beta の通常 window と InPrivate window が開いた。
- Spotify: 初回は起動が遅く、5秒待った後の2回目で Windows 版 window を確認した。
- Signal / Obsidian: Windows 版 window を確認した。
- 1Password: Windows 版の起動 process と MainWindow を確認した。computer-use の window 一覧で初期表示は確認できず、完全な GUI 操作成功とは扱わない。
- ChatGPT: Windows native app が前面になった。
- HEY Calendar / Email: Windows ブラウザでそれぞれ HEY の sign-in tab が開いた。サービスへのログインは行っていない。
- Google Messages / WhatsApp: Windows ブラウザでそれぞれ web ページが開いた。

## Ghostty の実キー確認

| キー・操作                                 | 状態     | 観測・制約                                                                                                             |
| ------------------------------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| `Ctrl+Shift+E`: 上下分割                   | 確認済み | pane が上下に分かれた                                                                                                  |
| `Ctrl+Shift+O`: 左右分割                   | 確認済み | pane が左右に分かれた                                                                                                  |
| `Ctrl+Alt+矢印`: pane 移動                 | 確認済み | 3 pane layout で Left / Right / Up / Down の全方向で active pane の移動を確認                                          |
| `Win+Ctrl+Shift+矢印`: 10ピクセル変更      | 確認済み | Left / Right / Up / Down の全方向を確認。下段の縦 divider は Left で425→415px、Right で425pxへ復元。上下も変更後に復元 |
| `Win+Ctrl+Shift+Alt+矢印`: 100ピクセル変更 | 確認済み | Right / Up / Down / Left の各方向で pane 境界の100ピクセル変更を確認。上下は元に復元                                   |
| `Ctrl+Shift+T`: tab 追加                   | 確認済み | 新しい tab が開いた                                                                                                    |
| `Ctrl+Shift+矢印`: tab 移動                | 確認済み | 9 tab で Left は9→8、Up は8→7、Right は7→8、Down は8→9へ移動し、全方向を確認                                           |
| `Alt+1..9`: tab 指定                       | 確認済み | 9 tab を作成し、実キー Alt+1〜9 が表示順の該当 tab を選択することを確認。1番目は元の3 pane layout                      |

## 設定・自動検査

| 対象                   | 結果                                                              | 確認範囲                                                                                                                                                                                                                     |
| ---------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nix unit               | 185件成功                                                         | 共通定義、export、renderer、WSLg transport、WSL GUI package、日本語フォント配置、Chrome GTK3 cache などの値・契約                                                                                                            |
| Ghostty                | 28割り当ての設定検査成功                                          | 配置済み設定の構文・action。実キー入力の成功とは別                                                                                                                                                                           |
| Neovim                 | 配置済み17割り当てと Oil runtime を確認                           | 実際に配置した Neovim 設定を読み込む runtime 検査。全キーを GUI から押した検査ではない                                                                                                                                       |
| PowerShell 全体        | 914件成功・失敗0件・POSIX 境界1件 skip / 全915件、coverage 81.96% | Windows native の公式 runner を `MinimumCoverage=80` で実行し exit 0、191.4秒。対象10ファイルの command coverage は2689 / 3281、未カバー592。CI の MSI 中断検出、runtime 準備、更新失敗の厳格判定と PATH 隔離を含む作業 tree |
| Windows action runtime | 155件成功                                                         | 中間 snapshot の対象 runtime 検査。後続の通知修正は下の61件 focused と最新の全件検査で確認                                                                                                                                   |
| 通知 focused           | 61件成功                                                          | 最新の通知削除・全削除と完了判定の対象検査                                                                                                                                                                                   |

Nix unit は185件成功し、構成の lint 修正後の出力は /nix/store/vq2k8hn4hh8gr4cidg56iqqydbg1ryzw-nix-unit-check です。WSLg の UDEV 配置、GTK 3 / 4 と設定ポータル、dconf service、Nautilus の package 所有境界も含みます。

Windows native の全件検査は914件成功・失敗0件、coverage 81.96%で80%基準を満たし、exit 0 で成功しました。実行前後で `scripts/powershell/` と Windows manifest の source hash が一致しました。証跡は `%TEMP%/dotfiles-pr731-strict-final-powershell80.log`、同名の `.xml`、`-coverage.xml`、`-source-before.json`、`-source-after.json` です。その後に PowerShell 5.1 の JSON 引数を修正したフォント検査9件も、5.1 / 7 の両方で成功しました。追加の証跡は `%TEMP%/dotfiles-pr731-font-winps51-green.log` と `dotfiles-pr731-font-pwsh7-green.log`、同名の `.xml` です。WSL からの `task commit` では Windows PowerShell hook の Linux branch がテストを実行せず exit 0 となるため、Pester の結果は Windows native の公式 runner で取得します。

整形済み runtime を `task chezmoi` で再適用し、配置した runtime の正規化した内容がソースと一致することを確認しました。Ghostty の28割り当ては全て実キーで確認済みで、検査のために追加した tab は整理済みです。

夜間モードは修正後に状態変更を確認し、Ghostty の pane 移動・10 / 100ピクセル resize・tab 移動の全方向と Alt+1〜9 の tab 指定を確認しました。URL の JSONL 保存、録画 overlay の起動、撮影画像の PNG 保存・clipboard 取得、修正後の Paint 編集起動、Ghostty のコピー・貼り付け、直近の通知削除と全通知削除も確認しました。録画開始・ファイル作成、複数音声出力の巡回など、表で未確認とした操作は実機での成功として扱いません。

実機確認中にユーザーの物理 Escape 操作で computer-use が停止しました。その後、ユーザーが UI 検証の再開を承認し、上記の WSLg アプリ起動・resize・夜間モード・応答不可を確認しました。

## 日本語表示

WSL Chrome の client / headless で日本語 UTF-8 locale と CJK sans / serif の表示を確認しました。修正前の通常 X11 window は本文の日本語が正常で、WSLg の灰色の titlebar だけに tofu / hex 表示が残りました。X11 の client-side decoration を使う隔離 profile では title・本文・serif の日本語表示を確認しました。既存の Chrome profile は変更していません。

WSLg system distro の読み取り調査では、当初 `fc-match` は FreeSans、`fc-list :lang=ja` は空でした。ユーザー distro の `/usr/local/share/fonts` に通常ファイルとして Noto Sans CJK を一時配置した後は、system distro の `fc-match` が Noto Sans CJK JP / Bold を選び、新しい Pango の `--no-display` PNG でも日本語を正常に描画しました。

恒久設定の `nix/hosts/x86_64-linux/wsl/fonts.nix` を含む `nixos-rebuild switch` が成功し、activation `wslgFonts` の実行を確認しました。`/usr/local/share/fonts/dotfiles-wslg/NotoSansCJK-VF.otf.ttc` は通常ファイル、32,682,580 bytes、mode `0644`、owner `root:root` で配置されています。SHA256 は `d3d8256cdec8dbcb3552284bc6b20c734dd60c2ee9df83b5758e34807c4bac32` で固定した Nix の入力と一致しました。WSLg system distro の `fc-cache` / `fc-match` でも、この本番配置先の Noto Sans CJK JP Bold を選択しています。一時検査用フォントは削除済みです。

フォント反映時の system は `/nix/store/9fy43irl4bjahgrf93gj78las0670p68-nixos-system-nixos-26.11.20261011.7fd4004` です。activation 内では WSLg を再起動しません。実行中の Weston が古い Pango font map を保持していたため、ユーザーの承認後に `wsl --shutdown` で WSL 全体を再起動しました。その後 `Win+Shift+B` で WSLg Chrome を起動し、通常 X11 の灰色の server titlebar が「新しいタブ - Google Chrome」と日本語で正常表示されることを実 UI で確認しました。恒久フォント配置と再起動後の通常 titlebar の確認が完了しています。

## CI の中断検出とテスト環境

PR #731 の初回 head `4b3d6dbbb455f0646fff5a0cb563bf687bba9a3b` では、Windows の PowerShell MSI 更新で検証用の PowerShell 7 が終了し、子プロセスの後処理と成功検証が実行されませんでした。親が exit 0 だけを信頼したため工程が成功扱いになり、テスト用の長い User PATH が後続へ残りました。

User PATH の保存・seed・復元を安定した Windows PowerShell 5.1 の親へ移し、子の完了証跡がない exit 0 も失敗にしました。MSI runtime の準備は同じ Windows manifest の PowerShell 宣言と通常の WinGet handler を使って先に行い、実 installer での全 package の検証義務は維持します。この準備では `WingetRequireSuccessfulUpdate` を有効にし、更新失敗後に古い実行環境を維持した場合も失敗として扱います。実インストールや実ユーザーのレジストリ変更を行わない fixture で、早期 exit 0 と強制終了後の復元を検査しています。

長い PATH を注入した隔離 fixture では Winget / AppX の7件の失敗を再現し、unit test の PATH を実ユーザー環境から分離した後は158件成功しました。Bats の古い期待値も、管理ファイル3件と配布スクリプト4件の完全一致へ更新し、対象2件と `wezterm-config` build が成功しています。ローカル NixOS で Bash 全体を直接実行した際の43件の setup 失敗は Python / FHS tool の不足であり、Bash 全体の CI 判定は依存を備えた devcontainer の実行結果を使います。

初回 CI の PowerShell 5.1 側は実 installer と User PATH の復元が完了し、後続のフォント検査9件だけが JSON の引用符で失敗しました。検査から chezmoi を起動する際に共通の引数処理ラッパーを使い、5.1 / 7 の両方で実 chezmoi による9件を確認しています。runtime 準備と中断検出、更新失敗の厳格判定を含む5.1の対象検査は211件成功・POSIX 境界1件 skipでした。

修正後の Windows PowerShell 5.1 全体も907件成功・失敗0件・既存の runtime 境界8件 skip / 全915件、197.71秒、exit 0 で確認しました。実行前後の source hash は一致しています。証跡は `%TEMP%/dotfiles-pr731-release-winps51.log`、同名の `.xml`、`-source-before.json`、`-source-after.json` です。

次の CI head `792f85b04f138cb993c41f69471dbdc1bf1372e9` で、5.1 の `-File` 起動では既定引数の評価時に `$PSScriptRoot` が空になることを確認しました。既定の repository 解決をスクリプト本文へ移し、実際の5.1プロセスで起動する回帰検査を追加しています。package 操作だけを無害な出力へ置換し、引数・起動処理は本番のまま検査しました。対象5件は5.1 / 7の両方で成功し、証跡は `%TEMP%/dotfiles-pr731-entrypoint-winps51-green.log` と `dotfiles-pr731-entrypoint-pwsh7-green.log`、同名の `.xml` です。

## レビューの追加検証

`nix/outputs.nix` だけを変更した場合も Windows / chezmoi の検査を選択するよう CI 分類を修正しました。実際の Git 差分と composite action を使う回帰検査で分類漏れを再現し、修正後は対象8件と Python のトップレベル52件が成功しています。

PowerToys 用の managed file 置換には `-ErrorAction Stop` を指定しました。実 chezmoi で展開した配布スクリプトを隔離した子プロセスで実行し、action script と JSON の各配置先を実際にロックすると、修正前は成功終了してしまうことを再現しました。修正後は非0終了・PowerToys 同期の未実行・既存内容の保持・一時ファイル削除を確認しています。正常時の UTF-8 / BOM、再適用での更新時刻保持、Linux / Darwin の配布境界も含む5件が、Windows PowerShell 5.1 / 7 の両方で成功しました。同期先には fixture を使い、実ユーザーの PowerToys は変更していません。証跡は `%TEMP%/dotfiles-pr731-deployment-{winps51,pwsh7}-green.log` と同名の `.xml` です。

## Windows Dia

Windows 用 manifest の `direct` source から公式 MSIX の Dia 1.1.0.6 を導入しました。実際の登録情報、package family / publisher / architecture / version、実行ファイル、`appxLaunchTarget` の検証に成功しています。再実行では導入済みとして追加ダウンロードを行いませんでした。

初回の実機導入で、既に導入済みの VCLibs を再登録して使用中のアプリと競合する問題が判明しました。健全な同等以上の依存 package を検出して利用するよう修正した後、導入に成功しました。共有アプリの強制終了は行っていません。

起動後に `Dia` の window が一覧へ現れたことを確認しました。その後、操作ツールが Dia の browser URL policy に未対応として停止したため、画面内の内容・認証操作は確認していません。WSL のブラウザーキーは引き続き Chrome を起動します。

## Files と UDEV の追加確認

`Win+Shift+F` で NixOS-WSL の Nautilus（Files）を起動し、承認済みの WSL 全体再起動後にも同じキーで開くことを確認しました。日本語のファイル名を含む専用 fixture で `Win+C/V` によるコピー、`Win+X/V` による移動を確認しています。内容の SHA256 はいずれも `a2f8068b7399d73a2f7ae9b776874d64d2a1754c4490310b188165fedaff1c50` と一致し、移動元のファイルが消えたことも確認しました。

当初のコピー失敗は、WSLg metadata 内の別 window の負の AppID 応答が Nautilus の既知の識別結果を消していたためです。window ID を比較してから対象の結果だけを更新するよう修正しました。対象自身の負の応答や破棄、provider の再利用では識別結果を解除する契約を維持しています。

UDEV 配置と chezmoi 反映後に WSL 全体を再起動し、Weston の実環境の `FONTCONFIG_FILE` を確認しました。同じ環境で Sans Regular / Bold、日本語、Nerd glyph が UDEV、emoji が Noto Color Emoji に解決されています。通常 Chrome の server titlebar は UDEV で「新しいタブ - Google Chrome」と正常表示されました。

GTK 3 / 4 の配置済み設定と実行中の設定ポータルは `UDEV Gothic NF 11` を返し、Nautilus の画面内フォント・日本語ファイル名も確認しました。反映済み system は `/nix/store/5y68zhqsmb5zjp74k5440gl03ymidfkz-nixos-system-nixos-26.11.20261011.7fd4004` です。

## 日本語入力

一時 GTK3 cache を明示した隔離 Chrome で、実キーの `Ctrl+Space` により「あ (Hiragana)」popup が開き、fcitx の状態2を確認しました。続けて `n i h o n g o` を入力すると「にほんご」、`Space` で「日本語」、`Enter` で確定することを実 UI で確認しました。

原因は GTK3 が fcitx plugin を発見するための登録 cache が欠けていたことです。`nix/modules/browsers/chrome/default.nix` は `fcitx5-gtk` から immutable な `immodules.cache` を生成し、WSL 専用 Chrome wrapper の `GTK_IM_MODULE_FILE` に指定します。既存の X11 / fcitx 設定と入力切り替えキーは維持します。

この修正を含む `nixos-rebuild switch` は成功し、system の store hash は `0zarpnnizn4cp7nw8hzbzvn3lnzl2a2v` です。通常の `BROWSER` command path が新 wrapper / cache を指すことも確認しました。

旧検査用 Chrome window を閉じ、`Win+Shift+B` で通常 wrapper から新しく起動した Chrome（PID `5905`）でも再確認しました。入力欄のある検査用 HTML で `Ctrl+Space` により「あ (Hiragana)」popup と fcitx の状態2を確認し、実キー `a` で「あ」を入力して `Enter` で確定しました。最後に `Ctrl+Space` でもとの inactive 状態1へ復元しました。通常起動でひらがなの入力・確定を確認済みです。「にほんご → 日本語」の漢字変換は上記の隔離 Chrome で確認した結果です。

Windows 操作の失敗は画面に表示し、`%LOCALAPPDATA%/dotfiles/keybindings/actions.log` に記録します。配布方法と各 OS での代替動作は [所有範囲と運用](./omarchy.md)、キー一覧は [キーバインド](./keybindings.md) を参照してください。
