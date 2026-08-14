# Unified terminal window-manager keybindings

## Context

tmux、Herdr、WezTerm、Windows Terminal、macOS Terminal.app では、同じ概念に
異なるキーが割り当てられている。操作対象も Session、Workspace、Tab、Pane と
ツールごとに異なるため、Terminal を切り替えるたびにキー体系を覚え直す必要が
ある。

window-manager 操作を単一の prefix と suffix 契約へ置換する。各ツールが持たない
概念を無理に模倣せず、対応可能な操作だけを同じキーで提供する。

## Goals

- 全対象の window-manager prefix を `Ctrl+Space` に統一する。
- Workspace、Tab、Pane、Session の suffix を共通化する。
- 旧 window-manager binding を削除し、新体系へ置換する。
- macOS Terminal.app と Windows Terminal のネイティブ操作も同じ2ストロークで
  実行できるようにする。
- 外側の Terminal と内側の tmux/Herdr を明示的に操作し分けられるようにする。
- パッケージ、設定、自動起動、ドキュメント、テストを dotfiles で管理する。

## Non-goals

- ツールが持たない概念を別機能で擬似的に実装しない。
- Terminal.app の分割表示を独立した上下・左右 Pane として扱わない。
- window-manager と無関係な編集、選択、クリップボード操作は変更しない。
- Neovim と tmux の境界を越える直接 `Ctrl+H/J/K/L` は削除しない。

## Concept mapping

| 共通概念  | tmux        | Herdr              | WezTerm    | Windows Terminal | Terminal.app |
| --------- | ----------- | ------------------ | ---------- | ---------------- | ------------ |
| Workspace | Session     | Workspace          | Workspace  | 非対応           | 非対応       |
| Tab       | Window      | Tab                | Tab        | Tab              | Tab          |
| Pane      | Pane        | Pane               | Pane       | Pane             | 分割表示のみ |
| Session   | Session全体 | persistent Session | Mux Domain | 非対応           | 非対応       |

tmux の Session は Workspace と detach 単位の両方を担う。`w` は Session picker、
`g` は Session、Window、Pane を含む全体 navigator として区別する。

## Common key contract

すべての操作は `Ctrl+Space` の後に suffix を入力する。

| 対象      | suffix                | 操作                 |
| --------- | --------------------- | -------------------- |
| Workspace | `w`                   | pickerを開く         |
| Workspace | `a`                   | 新規作成             |
| Workspace | `j` / `k`             | picker内で次／前     |
| Tab       | `n`                   | 新規作成             |
| Tab       | `q`                   | 閉じる               |
| Tab       | `Tab`                 | 次へ                 |
| Tab       | `Shift+Tab`           | 前へ                 |
| Pane      | `h` / `j` / `k` / `l` | 左／下／上／右へ移動 |
| Pane      | `v`                   | 左右分割             |
| Pane      | `-`                   | 上下分割             |
| Pane      | `x`                   | 閉じる               |
| Session   | `g`                   | navigatorを開く      |
| Session   | `d`                   | detach               |

Workspace picker 内の `j` / `k` は picker が開いている間だけ有効で、通常の
`prefix+j` / `prefix+k` は Pane 移動として扱う。

## Capability boundaries

- Herdr は全操作をネイティブに提供する。
- tmux は WorkspaceをSession、TabをWindowとして提供する。`d`はdetach、`g`は
  `choose-tree` 相当の全体 navigator とする。
- WezTerm は Workspace、Tab、Pane を提供する。`w`はWorkspace picker、`a`は名前を
  入力して新規Workspaceを作成する。`g`はWorkspace、Tab、Mux Domainを含むlauncher、
  `d`は現在のMux Domainがdetach可能な場合だけdetachし、それ以外は何もしない。
- Windows Terminal は Tab と上下・左右 Pane、Pane focusを提供する。Workspaceと
  Sessionは非対応とする。
- Terminal.app は Tab、単一の2ペイン分割、分割解除だけを提供する。`v`を分割、
  `x`を分割解除へ割り当てる。`-`、Pane focus、Workspace、Sessionは非対応とする。
- 非対応の外側操作を内側のtmux/Herdrで実行するときは、nested prefixを使う。

## Architecture

`docs/chezmoi/keybindings.md` を人が読む共通契約の正本とし、各ネイティブ設定を
アダプターとして管理する。設定形式の異なる5系統を生成コードで抽象化せず、
Pesterテストで契約との一致と旧binding不在を検証する。

### Native adapters

- `chezmoi/dot_tmux.conf`: tmux prefix、Session、Window、Pane操作
- `chezmoi/dot_config/herdr/config.toml`: Unix Herdr操作
- `chezmoi/AppData/Roaming/herdr/config.toml`: Windows Herdr操作
- `chezmoi/terminals/wezterm/wezterm.lua`: WezTerm操作とnested prefix転送
- `chezmoi/terminals/windows-terminal/settings.json`: Windows Terminal操作用の内部transport

Herdrの2設定は同一内容を維持する。

### macOS Terminal.app adapter

HammerspoonをHomebrew caskとして`nix/packages/sets.nix`へ追加し、
`~/.hammerspoon/init.lua`をchezmoi管理する。Terminal.appが前面のときだけ
`Ctrl+Space`をprefixとして捕捉し、以下の標準ショートカットを送る。

| suffix      | Terminal.appへ送るキー |
| ----------- | ---------------------- |
| `n`         | `Command+T`            |
| `q`         | `Command+W`            |
| `Tab`       | `Control+Tab`          |
| `Shift+Tab` | `Control+Shift+Tab`    |
| `v`         | `Command+D`            |
| `x`         | `Shift+Command+D`      |

Hammerspoonは`hs.autoLaunch(true)`でログイン時起動を維持する。Accessibility権限は
macOSの保護対象なので、初回だけユーザーが手動承認する。

### Windows Terminal adapter

AutoHotkey v2をWingetパッケージとして`nix/packages/sets.nix`へ追加する。スクリプトは
`%APPDATA%\dotfiles\terminal-keybindings.ahk`へchezmoiで配置し、Windows Startupの
ショートカットをrun-onchangeスクリプトで冪等に管理する。

AutoHotkeyは`WindowsTerminal.exe`が前面のときだけprefixを捕捉する。Windows
Terminalの`settings.json`にはユーザーが直接押さない`F13`から`F23`の内部transport
bindingを定義し、AutoHotkeyがsuffixを対応するtransport keyへ変換する。

| transport                     | 操作                      |
| ----------------------------- | ------------------------- |
| `F13` / `F14`                 | 新規Tab／Tabを閉じる      |
| `F15` / `F16`                 | 次／前のTab               |
| `F17` / `F18` / `F19` / `F20` | Pane focus 左／下／上／右 |
| `F21` / `F22`                 | 左右／上下分割            |
| `F23`                         | Paneを閉じる              |

## Nested prefix behavior

- `Ctrl+Space`、suffix: 外側のWezTerm、Terminal.app、Windows Terminalを操作する。
- `Ctrl+Space`、`Ctrl+Space`、suffix: 2回目のprefixを生の`Ctrl+Space`として内側へ
  送り、続くsuffixをtmuxまたはHerdrに処理させる。
- `Ctrl+Space`を所有する外側の管理層がないTerminalからtmuxまたはHerdrを直接
  使う場合は、通常どおり1回のprefixで操作する。

HammerspoonとAutoHotkeyは対象アプリ以外では入力を捕捉しない。WezTermは自身の
設定でnested prefixを処理するため、OS helperは介入しない。

## Prefix cancellation and failures

- suffix実行後または`Escape`入力時にprefix modeを終了する。Hammerspoon、
  AutoHotkey、WezTermはsuffixを1秒待ってtimeoutし、tmuxとHerdrは各native prefix
  modeの終了規則を使う。
- 未定義suffixと、その外側Terminalで非対応のsuffixは何も実行せず終了する。
- helperが停止している場合はTerminal標準キーがそのまま利用でき、Terminal起動や
  shell入力を妨げない。
- HammerspoonにAccessibility権限がない場合は設定を読み込んだまま標準操作へ
  フォールバックし、権限付与手順をドキュメントに表示する。
- AutoHotkey本体または管理スクリプトがない場合、Startup登録は明示的に失敗し、
  chezmoi apply全体へ成功を偽装しない。

## Migration

- tmuxの`C-a` prefix、旧Window作成・終了・移動bindingを削除する。
- WezTermの旧Tab・Pane・Workspace window-manager bindingを削除する。
- Windows Terminalの旧Tab・Pane bindingを削除し、内部transportだけを残す。
- Herdrの既定キーに依存せず、共通契約を明示的に設定する。
- editor navigation、クリップボード、検索、font、GUI window focusなど、対象外の
  bindingは維持する。
- ドキュメントは旧表を残さず、新しい契約とcapability boundaryへ置換する。

## Verification

テストを省略せず、変更に関連する全検証を実行する。

### Static and contract tests

- Pesterでtmux、Herdr、WezTerm、Windows Terminal、Hammerspoon、AutoHotkeyの
  prefixとsuffixを検証する。
- 旧window-manager bindingが残っていないことを検証する。
- HerdrのUnix/Windows設定が同一であることを検証する。
- HammerspoonとAutoHotkeyが対象アプリに限定されていることを検証する。
- Windows Terminalの内部transportがF13からF23だけであることを検証する。
- nested prefix転送とhelperの自動起動設定を検証する。
- HammerspoonとAutoHotkeyのパッケージproviderが生成物へ反映されることを検証する。

### Tool validation

- `herdr config check`で管理設定を検証する。
- `wezterm show-keys`で解決済みbindingを確認する。
- tmuxの一時serverで設定を読み込み、解決済みkey tableを確認する。
- `nix fmt -- --fail-on-change`、flake evaluation、Bats、Pester、PowerShell lint、
  `git diff --check`を実行する。
- Windows固有のAutoHotkeyとWindows Terminal契約はWindows CIで検証する。

### Runtime acceptance

- macOS Terminal.appでTab作成・終了・前後移動・分割・分割解除を確認する。
- WezTerm、Terminal.app、Windows Terminalから内側へnested prefixが届くことを
  各対応OSで確認する。
- tmux、Herdr、WezTermでWorkspace、Tab、Pane、Sessionの対応操作を確認する。
- GitHub Actionsをすべて通過させてからmergeする。

## Acceptance criteria

- 対応する全ツールで`Ctrl+Space`と共通suffixが同じ意味を持つ。
- Terminal.appとWindows TerminalのネイティブTab・Pane操作が共通体系で動く。
- 非対応機能は誤った類似機能を起動しない。
- nested prefixで内側のtmux/Herdrを操作できる。
- 旧window-manager bindingが削除され、対象外bindingは維持される。
- インストール、設定、自動起動、ドキュメント、テストがdotfilesで再現可能である。
