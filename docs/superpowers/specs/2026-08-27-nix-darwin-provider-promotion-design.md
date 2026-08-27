# nix-darwin Provider Promotion Design

> **Status:** Approved in chat on 2026-08-27; implementation pending written-spec review.

## Goal

macOS のパッケージ管理を Nix derivation に統一し、現在 Homebrew cask または formula で管理している 13 件を、製品同一性と実機動作を確認しながら 1 件ずつ移行する。移行後は nixpkgs と公式配布物の更新を定期監査し、より適切な provider への変更を検証済み Pull Request として自動提案する。

成功条件は次のとおり。

- 対象 13 件の Darwin provider がすべて `nix` になる。
- 同一カタログ ID が Nix と Homebrew の両方からインストールされない。
- `nix flake check` または nix-darwin 評価が provider 定義の矛盾を拒否する。
- upstream nixpkgs に同じ製品の健全な derivation がある場合はそれを使う。
- upstream に同じ製品がない場合は、公式配布物から独自 derivation を作る。
- GUI bundle は vendor 署名を壊さず、bundle ID、実行ファイル、起動を確認する。
- Ollama は GUI cask を廃止し、`pkgs.ollama` と nix-darwin launchd service を使う。
- 旧 Homebrew package は Nix 版の検証成功後にのみ削除し、ユーザーデータは削除しない。
- 現在の移行はパッケージ単位のコミットに分け、全件完了後に 1 本の Pull Request として公開する。
- 将来の version/provider 更新は CI が Pull Request を作成し、自動マージしない。

## Current State and Problem

`nix/packages/sets.nix` はパッケージカタログの SSOT だが、現在の `resolve` は `pkg` が存在し、対象 platform をサポートするかだけを確認する。`support.<platform>.provider` は解決時に参照されない。

そのため、1 つのエントリに Darwin 対応の `pkg` と `homebrew-cask` provider が共存すると、Home Manager が Nix package を、nix-darwin が Homebrew cask をそれぞれインストールできる。カタログ上は provider を 1 つ選んだように見えても、実際のインストール集合は重複する。

`providerErrors` は provider または reviewed unsupported reason の欠落を検出するが、次の意味的矛盾は検出しない。

- 選択 provider と実際に解決された package の不一致
- provider 固有フィールドの欠落または余分な指定
- `unsupported` と provider の同時指定
- Nix と Homebrew のインストール集合の重複
- nixpkgs の同名別製品の誤選択

また、Dependabot は GitHub Actions だけを更新する。`nix flake update` は version を更新するが、新しい Darwin derivation が nixpkgs に追加されても custom/Homebrew provider からの移行を提案しない。

## Scope

### In scope

現在 Darwin で Homebrew 管理されている次の 13 件を移行する。

| Catalog ID       | New source         | Runtime identity                |
| ---------------- | ------------------ | ------------------------------- |
| `_1password-gui` | nixpkgs            | `com.1password.1password`       |
| `chatgpt`        | nixpkgs            | `com.openai.codex`              |
| `dia-browser`    | custom derivation  | `company.thebrowser.dia`        |
| `discord`        | nixpkgs            | `com.hnc.Discord`               |
| `docker-desktop` | custom derivation  | `com.docker.docker`             |
| `google-chrome`  | nixpkgs            | `com.google.Chrome`             |
| `hammerspoon`    | custom derivation  | `org.hammerspoon.Hammerspoon`   |
| `ollama`         | nixpkgs CLI/server | `ollama` command and port 11434 |
| `orca-editor`    | custom derivation  | `com.stablyai.orca`             |
| `raycast`        | nixpkgs            | `com.raycast.macos`             |
| `tart`           | nixpkgs            | `tart` command                  |
| `vscode`         | nixpkgs            | `com.microsoft.VSCode`          |
| `wezterm`        | nixpkgs            | `com.github.wez.wezterm`        |

`pkgs.dia` は GNOME diagram editor、`pkgs.orca` は GNOME screen reader であり、対象製品ではない。名前が一致しても候補にしない。

Ollama は現在の `ollama-app` と同一の GUI を維持しない。nixpkgs の `pkgs.ollama` は CLI/server package であり、nix-darwin launchd service として host の推論 backend を提供する。

### Out of scope

- Windows と Linux の既存 provider の変更
- カタログ外で導入されるソフトウェアの全面移行
- model file を Nix store に格納すること
- 自動生成 Pull Request の自動マージ
- 製品名だけを使った nixpkgs attr の探索
- Homebrew 自体の即時削除。対象 13 件の provider としては使用しないが、他の既存責務は別変更とする。

## Package Catalog Model

`nix/packages/sets.nix` を SSOT として維持する。各 Darwin provider は、provider の種類に加えて source と製品 identity を持つ。

```nix
support.darwin = {
  provider = "nix";
  source = "nixpkgs"; # または "custom"
  nixAttr = "chatgpt"; # nixpkgs source の場合は必須
  identity = {
    homepage = "https://openai.com/chatgpt/desktop/";
    bundleId = "com.openai.codex";
    executable = "ChatGPT";
  };
};
```

CLI/service package は `bundleId` の代わりに `command` を持つ。custom source は `nixAttr` を持たず、カタログの `pkg` が repository 内の package definition を参照する。将来の upstream 候補は、自動推測せず package ID に対応する監査 registry へ明示する。

`supportReport` は derivation 自体を JSON 化せず、provider、source、attr 名、identity、verification profile だけを出力する。更新ツールと CI はこの評価済み report を入力とし、`sets.nix` を独自 parser で解釈しない。

## Provider Resolution and Assertions

`resolve` は現在の host platform に対して `support.<platform>.provider == "nix"` のエントリだけを Home Manager package list へ含める。`homebrew-cask`、`homebrew-formula`、`system-manager`、`winget`、`msstore`、`unsupported` は Nix user package として解決しない。

正しい解決処理に加えて、Nix 評価時の assertion を設ける。最低限、次を拒否する。

- 1 package/platform に provider と `unsupported` が同時に存在する。
- `provider = "nix"` なのに `pkg` が null、derivation でない、または platform 非対応である。
- `provider = "nix"` なのに `source` または identity がない。
- `source = "nixpkgs"` なのに `nixAttr` がない。
- `homebrew-cask` なのに `cask` がない、または他 provider 固有フィールドが残る。
- `homebrew-formula` なのに `formula` がない、または他 provider 固有フィールドが残る。
- 同じ catalog ID が Nix package set と Darwin Homebrew set の両方へ解決される。

エラーは package ID、platform、競合 provider を含む。`providerErrors` と package support check を拡張し、`nix flake check`、CI、`darwin-rebuild` の評価で不整合を失敗させる。

treefmt、statix、deadnix は書式または一般的な静的問題を扱い、この domain rule の検証手段とはしない。

## Nix Package Implementation

### Upstream packages

`_1password-gui`、ChatGPT、Discord、Google Chrome、Ollama、Raycast、Tart、VS Code、WezTerm は、lock された nixpkgs の対応 derivation を使う。

VS Code は `pkgs.vscode` をそのまま使う。既存の `useVSCodeRipgrep = false` override と `postPatch` は署名済み app bundle を変更して署名を無効化するため削除する。Darwin GUI derivation は原則として vendor bundle を fixup しない。

### Custom packages

Dia Browser、Stably Orca、Hammerspoon、Docker Desktop は `nix/packages/<package>/default.nix` に分離する。各 package は次を満たす。

- vendor の公式 HTTPS 配布元だけを使用する。
- version と content hash を固定する。
- DMG/archive から `.app` を `$out/Applications` へコピーする。
- vendor 署名済み bundle 内を変更しない。
- Darwin fixup を無効化し、署名を保持する。
- `meta.platforms`、`meta.homepage`、license、source provenance を宣言する。
- 必要な CLI が app bundle 内にある場合だけ `$out/bin` から symlink または wrapper を提供する。
- update script は version URL と hash だけを更新し、provider identity を変更しない。

custom package の出力は nix-darwin/Home Manager の application linking により `/Applications/Nix Apps` から利用する。

### Ollama service

Ollama は `pkgs.ollama` を user package として導入し、nix-darwin launchd agent で `ollama serve` を管理する。service は optional install feature `WithOllama` が有効な場合だけ作成する。

service readiness は `http://127.0.0.1:11434/api/tags` で確認する。model、cache、履歴は user writable directory に置き、Nix store へ含めない。既存の `open -a Ollama` による GUI 起動処理は削除する。

### Docker Desktop activation

Docker Desktop の derivation は公式 app bundle を変更せず配置する。privileged helper、socket symlink、CLI link は Nix build sandbox ではなく nix-darwin activation が vendor 提供の `Docker.app/Contents/MacOS/install` interface を使って収束させる。

activation は現在の user を明示し、license acceptance を明示的な repository setting として扱う。設定が有効でない場合は `--accept-license` を暗黙に渡さず、評価または activation を説明付きで失敗させる。root command は derivation に固定された executable path を使用し、PATH 上の別 Docker.app を実行しない。

Docker runtime は `WithDocker` が有効な場合だけ起動する。起動後は `docker info` が成功するまで bounded timeout で待機し、失敗時に後続の optional runtime setup を実行しない。

## Migration Flow

作業は `codex/nix-darwin-provider-promotion` の独立 worktree で行う。元 checkout の未コミット `flake.lock` は変更せず、更新内容を作業 worktree へ複製して検証対象の nixpkgs revision とする。

各 package は次の順序で移行する。

1. package definition、catalog metadata、Nix assertion、回帰 test を追加または更新する。
2. `aarch64-darwin` derivation を build する。
3. bundle ID、executable、`codesign --verify --deep --strict`、必要な CLI を検証する。
4. nix-darwin で実機へ反映する。
5. package 固有の acceptance check を実行する。
6. acceptance 成功後に旧 cask/formula を通常の `brew uninstall` で削除する。
7. Homebrew package がなく、Nix package だけが有効であることを再検査する。
8. その package の変更を個別コミットにする。

`brew uninstall --zap` は使用しない。ユーザー設定、認証、cache、VM、model は削除しない。現在 `homebrew.onActivation.cleanup = "none"` であるため、カタログから cask を外すだけでは既存 install は削除されない。移行期間は明示的な legacy provider cleanup を使い、Nix package の導入確認後だけ旧 package を削除する。

途中で package acceptance が失敗した場合、その package の Homebrew provider は削除せず、同じ package を修正してから次へ進む。すでに成功した package は戻さない。

## Package Acceptance Checks

- GUI application: expected bundle ID、expected executable、vendor signature、Gatekeeper assessment、`open` による起動。
- VS Code: `code --version`、app 起動、署名検証。
- 1Password: app 起動と `op` desktop integration probe。secret の内容はログへ出さない。
- Ollama: launchd 状態と `/api/tags` 応答。
- Docker Desktop: app 起動、privileged setup、`docker info`。
- Tart: `tart --version` と既存 VM list の read-only probe。
- WezTerm: `wezterm --version`、terminfo、app 起動。
- Hammerspoon: app 起動と既存 configuration load の確認。
- Dia Browser、Orca、ChatGPT、Discord、Chrome、Raycast: bundle identity、署名、起動。

アプリ起動により現在のセッションへ影響する場合は、build/静的検証を先に完了し、実機 acceptance の直前に対象と影響を通知する。

## Automated Version and Provider Promotion

Darwin package audit workflow を週次、manual dispatch、`flake.lock` または provider registry の変更時に実行する。

workflow は次の 2 種類の更新を扱う。

### Version update

- nixpkgs source は更新された `flake.lock` の package version を使って build と acceptance-compatible check を実行する。
- custom source は package 固有 update script で公式 version と hash の変更候補を生成する。
- generated diff が version、URL、hash 以外を変更した場合は PR を作らず失敗する。

### Provider promotion

- custom package ごとに明示された nixpkgs attr 候補だけを調べる。
- attr の存在、`aarch64-darwin` support、homepage、bundle ID または command identity を確認する。
- macOS runner で build と package acceptance-compatible check を実行する。
- 成功した場合だけ `source = "nixpkgs"` と `nixAttr` を更新する Pull Request を作る。
- 候補がない、別製品である、build または identity check が失敗した場合は現在の custom provider を維持し、workflow summary に理由を残す。

provider は local evaluation 中に暗黙切替しない。`nrs` は lock 更新による version 変更を適用できるが、custom から nixpkgs への source 変更は検証済み commit が main に入った後だけ起きる。

workflow-created Pull Request は自動マージしない。通常の repository ruleset、CI、review を通す。

## CI Architecture

既存の Linux `Package Consistency` job は provider metadata、assertion、generated Windows manifest の整合性を検証する。Darwin package 専用 workflow を追加し、macOS Apple Silicon runner で実 package を検証する。

通常の Pull Request では変更 path と catalog diff から影響 package だけを matrix 化する。週次監査と manual full run は 13 件すべてを対象にする。package selection が空でも required workflow が pending にならないよう、常に実行される軽量 contract job を持たせる。

CI は secret や user state を必要としない範囲の build、bundle identity、署名、CLI smoke test を担当する。1Password desktop integration、Docker daemon、GUI の視覚的起動など host state を必要とする検証は実機 acceptance として分離する。

## Error Handling and Safety

- upstream attr の評価失敗を custom provider への暗黙 fallback として隠さない。
- provider audit が失敗しても main の provider は変更しない。
- download source、version、hash、identity のどれかが確認できない custom update は拒否する。
- vendor-signed bundle を patch または fixup する必要がある package は、署名を壊した状態で採用しない。
- Homebrew removal は Nix package の acceptance 後に限定し、`--zap` を禁止する。
- Docker license acceptance と privileged change は明示設定なしで実行しない。
- 1Password、Docker、Ollama の probe は credential、model content、user data を出力しない。
- timeout を持たない GUI/service wait を作らない。

## Testing and Validation

実装で最低限、次を実行する。

- package catalog Bats tests
- macOS configuration Bats tests
- CI routing contract tests
- PowerShell package catalog tests。Windows provider が変わらないことを確認する。
- `nix fmt -- --check` 相当の repository formatting check
- `nix flake check --no-build --impure --all-systems`
- `nix eval` による Darwin package/provider set の確認
- 13 件の `aarch64-darwin` build または対応する binary-cache realization
- GUI bundle identity と codesign check
- package 固有の実機 acceptance check
- Homebrew/Nix 重複がゼロであることの最終監査

baseline の `nix flake check --no-build --impure --all-systems` は、変更前から `bootstrap-nixos-vm` の `users.users.nixos.isNormalUser` と `users.users.nixos.group` assertion で失敗する。この既存不具合は今回の Darwin provider scope には含めない。最終結果では、同じ既知失敗以外に新しい失敗がないことを分離して報告する。

## Commit and Pull Request Strategy

カタログ assertion と監査基盤を先にコミットし、その後は 13 package を 1 件ずつコミットする。Ollama service、Docker activation、自動 update workflow は責務ごとに独立コミットにする。

すべての package migration、実機 acceptance、CI contract が完了してから branch を push し、1 本の Pull Request を作成する。途中状態の Pull Request は作らない。

## Rollback

package 単位の commit を revert し、直前の catalog provider と Homebrew metadata を戻す。custom package または upstream package の導入に失敗した時点では旧 cask/formula を削除しないため、移行中の rollback は provider metadata を戻すだけでよい。

旧 Homebrew package 削除後の rollback は、カタログへ旧 provider を戻して nix-darwin を適用する。ユーザーデータは `--zap` で削除していないため、再インストール後に既存状態を再利用できる。
