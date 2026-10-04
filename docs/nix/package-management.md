# パッケージ管理

## Single Source of Truth

`nix/packages/catalog/` が全プラットフォームのアプリ・CLI の package と provider metadata の正本です。`nix/packages/sets.nix` は catalog、provider 選択、installer metadata を合成する公開入口であり、既存の consumer は引き続きこの入口を import します。

フォントパッケージと fontconfig 設定は `nix/modules/fonts.nix` の `fonts.packages` / `fonts.fontconfig` に一度だけ定義します。Darwin / NixOS のシステム構成はそれぞれ `nix/modules/darwin/default.nix` / `nix/modules/nixos/default.nix` を読み込み、OS 固有の option と配線はこの入口に記載します。NixOS は共通 module を import し、NixOS 専用の `fonts.fontDir.enable` を設定します。Darwin は `fonts.packages` を nix-darwin に、`fonts.fontconfig` を `home-manager.sharedModules` に渡します。Linux / WSL と standalone Darwin の Home Manager は各 entrypoint から共通定義を直接参照します。

共通の `fonts.fontconfig.defaultFonts` は `monospace` / `sansSerif` / `serif` を `UDEV Gothic NF`、`emoji` を `Noto Color Emoji` に設定します。Darwin での既定フォント設定は fontconfig を使うアプリに適用され、macOS 標準 UI / CoreText の既定フォントは変更しません。

## 分割の理由と編集先

SSOT は「各定義を一度だけ持つ」ことであり、すべてを 1 ファイルに置くことではありません。変更理由の異なる package データ、provider 選択、配布 metadata、host の動作を分け、パッケージ追加が OS 設定や選択ロジックの変更に広がらない構成にします。

| 編集先                                                                         | 責務・分割理由                                                                                      |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `catalog/{core,dev,terminal,editors,llm,desktop,system,k8s,infra}.nix`         | カテゴリごとの package と OS 別 provider metadata。各 package は 1 ファイルだけで定義する           |
| `catalog/context.nix`                                                          | カテゴリ間で共有する package 構築用の依存値                                                         |
| `catalog/default.nix`, `catalog/merge.nix`                                     | カテゴリの合成と重複定義の検出。後勝ちで上書きしない                                                |
| `providers/{common,normalize,selection,validation}.nix`                        | provider の共通処理、正規化、OS 別選択、coverage 検証。package データから分離する                   |
| `install/{default,node,windows-install,windows-verification,windows-only}.nix` | npm/pnpm 配布、Windows install/検証/専用アプリの metadata。provider 選択と installer 契約を区別する |
| `sets.nix`                                                                     | 上記を合成し、従来の export API を維持する小さい入口                                                |
| `<package>/default.nix`                                                        | custom derivation。既存パスを保ち、catalog から参照する                                             |
| `nix/home/keybindings/`                                                        | 共通キー配置・設定生成・ユーザー設定。パッケージの配布定義へ混在させない                            |
| `nix/hosts/`                                                                   | OS の service/有効化・競合解除。home 側の設定を消費し、キー配置を複製しない                         |

ディレクトリはすべて `nix/packages/` 相対です（表内で `nix/` から始まる行を除く）。カテゴリは探索と編集の単位であり、OS ごとに同じ package を再定義しません。[共通のキー割り当て](../chezmoi/omarchy.md) も同じ考え方で home に一度だけ定義し、host module は OS 統合と有効化を担当する構成です。

native desktop 用 package は `catalog/native-desktop.nix` に定義します。`sets.all` は全 feature を含むため、`installFeature` を付けるだけでは WSL/standalone への非混入を保証できません。`sets.nativeDesktopPackageNames` を使い headless Home Manager consumer で除外し、native host と選択された home module のみが `WithDesktop` で解決します。

| Catalog output                         | Consumer                            | Platform                                              |
| -------------------------------------- | ----------------------------------- | ----------------------------------------------------- |
| `darwinHomePackagesForInstallFeatures` | `nix/home/darwin.nix`               | macOS                                                 |
| `allWithout`                           | `nix/home/linux.nix`                | native NixOS、standalone Linux（Ubuntu、Debian など） |
| `allWithout`                           | `nix/home/wsl.nix`                  | NixOS-WSL                                             |
| `darwinCasksForInstallFeatures`        | nix-homebrew in nix-darwin          | macOS                                                 |
| `linuxSystemModules`                   | NixOS / System Manager modules      | Linux                                                 |
| `wingetMap`, `npmMap`, `pnpmGlobal`    | `nix/packages/winget.nix`           | Windows                                               |
| `supportReport`                        | `package-support-report` derivation | CI and review                                         |
| `providerErrors`                       | flake check                         | all platforms                                         |

Home Manager の package 選択と `home.packages` は各 OS の module が担当します。Darwin は install feature に応じて選択し、Linux は native desktop package を除外します。WSL は native desktop package に加えて Discord と Ollama を除外します。各 OS module が import する `nix/home/common.nix` は OS 非依存の共有設定を担当し、package 選択は行いません。

Windows だけに存在する GUI や OS component は `install/windows-only.nix` の `windowsOnlySupport` に置き、macOS/Linux で対応しない理由を必ず記録します。クロスプラットフォームのツールを理由なしに Windows-only へ入れることはできません。

macOS caskで`installFeature`を持つpackageは、installerが解決したprofileを
`darwinCasksForInstallFeatures`へ渡した場合だけHomebrew Bundleへ含まれます。

## Provider の追加

一般的な CLI は `catalog/` の該当カテゴリに Nix package と Windows provider を記述します。実際の schema は既存 entry に合わせてください。選択条件や coverage 検証の変更だけを `providers/` に置きます。

```nix
mypackage = {
  pkg = pkgs.mypackage;
  category = "dev";
  winget = "Publisher.Package";
};
```

macOS formula/cask や Linux system module が必要な application は、それぞれの provider metadata も同じ entry に追加します。どの OS にも provider がない場合は、その OS の `unsupported` reason が必要です。

## OS ごとの反映

通常は個別コマンドではなく one-command installer を再実行します。

```text
Windows:          install.cmd
macOS:            ./install.sh
NixOS:            ./install.sh
Ubuntu / Debian:  ./install.sh
```

- Windows は catalog から生成された winget/npm/pnpm manifest を PowerShell handlers が適用します。
- macOS は nix-darwin が Home Manager と nix-homebrew formula/cask を同じ switch に含めます。
- Ubuntu/Debian は System Manager が Home Manager と system package/service を適用します。
- NixOS は NixOS generation に Home Manager と system module を統合します。

アプリと OS 設定はこの OS 別構成を唯一の通常インストール入口とします。
`full`、`minimal`、カテゴリ別などの独立した Nix profile 用パッケージ集合は
公開しません。Tart の macOS guest も通常の `install.sh` を使います。
CI は OS configuration を build することで、その構成に含まれるアプリも検証します。
standalone Home Manager は上記の OS 統合を使えない環境向けに維持し、
manifest 生成・provider 検証の出力はインストール集合と分けて公開します。

macOS の `nrs` は nix-darwin を通じて Nix/Home Manager と宣言済み Homebrew provider を反映します。通常の CLI と Neovim・WezTerm は Nix 側で管理し、cask/formula は catalog が明示する例外です。Nix パッケージの版は `flake.lock` に従います。

### macOS の旧 provider サポート終了

旧 Homebrew provider を検出し、Nix provider の検証後に uninstall する
一度限りの自動移行は終了しました。通常インストールは現行 catalog の
provider を反映し、切替済みの旧 Homebrew package を自動 uninstall しません。
旧 provider の metadata と移行処理は提供しません。公開コマンド
`task darwin:migrate` は互換性のため残しますが、終了の案内だけを表示します。
旧引数は評価せず無視し、移行・検証・package やデータの変更は行いません。
現行 provider を個別に検証する `task darwin:verify` は引き続き利用できます。
既存 package やアプリのデータを整理する
必要がある場合は、利用者が保存対象と現在使用している実体を確認してから
個別に対応します。

インストール済み provider の検証成功は、既に起動している GUI application の
実体が切り替わったことを意味しません。切替完了を確認するときは、稼働中の
実行ファイル・bundle path も確認します。旧 bundle が使われている場合は、
利用者と作業の保存・再起動を調整してから現行 bundle への切替を確認します。
旧 package の残存だけを理由に自動削除することはありません。

2026-10-01 にこの作業端末を読み取り専用で確認しました。稼働中の
nix-darwin generation にある移行対象の有効な 8 package は現行 verifier に
成功し、`/Applications/Nix Apps` の 7 application は Info.plist と宣言済み
実行ファイルが generation の実体と一致しました。Tart は Nix profile の
実行ファイルでした。Google Chrome / Ollama の optional feature は無効でした。
一方、稼働中の Orca は `/Applications/Orca.app` の旧 bundle で、Homebrew の
cask receipt もこの path を指していました。検証済みの現行 Nix bundle は
`/Applications/Nix Apps/Orca.app` に別途配置されています。この端末の Orca の
稼働中 session の切替は未確認であり、残存 cask を未使用の重複とは扱いません。
この変更では終了・再起動・削除を行いません。
他端末の切替完了を保証する記録ではありません。

通常インストールは activation 後に `verify-darwin-packages.sh` で現行の
Nix application identity / CLI version を検証します。support report を一度
生成し、同じ metadata と output path を再利用します。無効な feature は
検証対象から外し、有効な package の欠落・identity/version 検証失敗は
後続の設定反映前にエラーとします。output path の report は optional
application をビルドする依存関係を持ちません。

単体の Nix application identity / CLI version 検証は
`task darwin:verify -- --support-json FILE --id ID --store-path PATH` で実行できます。
通常インストールの環境検証と各 profile の feature gate は維持します。

その他 Linux の `DOTFILES_ALLOW_USER_ONLY=1 ./install.sh` は Home Manager のみで、Docker や OS service は管理しません。

macOS で Homebrew cask の適用に失敗する場合は、
[Homebrew cask のトラブルシューティング](./homebrew-cask-troubleshooting.md)
を参照してください。

## 生成ファイル

Windows manifest は直接編集しません。更新時は以下を生成し、repository の JSON と一致させます。

```bash
nix build .#winget-export -o /tmp/winget-export
cp /tmp/winget-export/winget/packages.json windows/winget/packages.json
cp /tmp/winget-export/npm/packages.json windows/npm/packages.json
cp /tmp/winget-export/pnpm/packages.json windows/pnpm/packages.json
```

Windows の package install timeout は `packageInstallTimeoutSeconds = 3600`
（秒）を共通値とし、WinGet manifest、direct installer、Playwright の Chromium
install に使います。npm/pnpm/WinGet/WSL の runtime adapter も既定 3600 秒で、
`DOTFILES_INSTALL_TIMEOUT_SECONDS` による上書きを維持します。
direct installer でも環境変数を manifest の値より優先し、0 はダウンロードと
外部プロセスのタイムアウトを無効にします。不正な環境変数値や負数は無視し、
manifest の個別 timeout、未指定なら共通既定値を使います。
起動検証の既定と WSL の検証は 120 秒に延長します。既存の長い個別 timeout は
短縮せず維持し、catalog に明記された個別値を優先します
（例: Go は共通 install timeout）。

dsh と Gemini の `pnpmInstallArgs` は `--allow-build=!node-pty` を指定します。
既存の `allowBuilds.node-pty: true` を明示的な拒否へ更新し、ほかの許可は維持します。
Windows handler は選択済み manifest の拒否指定を集約し、検証済みパッケージの
skip 判定より前に `pnpm approve-builds -g !node-pty` を一度実行します。
このポリシー更新に失敗した場合は Apply を失敗として終了します。
この否定形には [pnpm 12.4.0 以降](https://pnpm.io/cli/add#--allow-build) が必要です。
Windows handler は既存 pnpm と bootstrap 後の実体のバージョンを検査します。
12.4.0 未満や使用不能な pnpm は Apply で npm/Corepack による再セットアップを
試み、必要なバージョンを準備できなければ失敗として報告します。

provider coverage は次で確認できます。

```bash
nix build .#package-support-report
cat result/package-support-report.json
```

`package-support-report` は各 catalog entry の Windows、Darwin、Linux provider または unsupported reason を記録します。自動推測できない provider gap は `providers/normalize.nix` の `reviewedUnsupported` に package 名と理由を明示し、新規 entry の未検討 platform は `checks.*.package-provider-coverage` で失敗させます。consistency CI は生成 manifest drift も失敗にします。

## システム package と Home Manager の境界

| 対象                                             | 管理先                                    |
| ------------------------------------------------ | ----------------------------------------- |
| shell から使う共通 CLI                           | Home Manager `home.packages`              |
| Docker daemon/socket、ユーザー group、OS service | NixOS / System Manager / nix-darwin       |
| macOS CLI                                        | 原則 Nix/Home Manager、明示例外は formula |
| macOS GUI application                            | catalog の Nix / cask provider            |
| Windows GUI/OS application                       | winget/msstore handler                    |
| shell、Git、terminal、editor 設定                | chezmoi                                   |

同じ package を Home Manager と system layer の両方へ重複させるのは、system service が絶対 path を必要とする場合に限定します。

Neovim 本体・プラグインはカタログを介さず、`nix/modules/nvim/` の Home Manager 設定で直接管理します。LSP・整形ツールは全エディタ共通の `nix/modules/lsp.nix` の `home.packages` に宣言し、通常の PATH に導入します。Cursor の LSP 設定は `nix/modules/cursor/` が管理し、Darwin／NixOS の共通 module が読み込みます。Tree-sitter の対象言語は `plugins.nix` の標準オプションに指定します。運用は [Neovim の運用](../chezmoi/neovim.md) を参照してください。

## 主なファイル

| File                                 | Responsibility                           |
| ------------------------------------ | ---------------------------------------- |
| `nix/packages/catalog/`              | package と provider metadata の正本      |
| `nix/packages/providers/`            | provider 選択、正規化、coverage 検証     |
| `nix/packages/install/`              | installer と manifest 用 metadata        |
| `nix/packages/sets.nix`              | 合成と既存 consumer 向けの公開 API       |
| `nix/packages/support-report.nix`    | coverage report derivation               |
| `nix/packages/winget.nix`            | generated Windows manifests              |
| `nix/home/darwin.nix`                | macOS Home Manager package 選択と設定    |
| `nix/home/linux.nix`                 | Linux Home Manager package 選択と設定    |
| `nix/home/wsl.nix`                   | WSL Home Manager package 選択と設定      |
| `nix/home/common.nix`                | OS 非依存の共有 Home Manager 設定        |
| `nix/hosts/darwin/configuration.nix` | macOS system and casks                   |
| `nix/system-manager/`                | Ubuntu/Debian system packages and Docker |
| `nix/hosts/linux/`                   | native NixOS system packages and Docker  |
| `nix/flakes/packages.nix`            | package sets, report, and checks         |

各 host は `nix/hosts/<host>/default.nix` を entrypoint、`configuration.nix` を実体とする分割を
標準とします。Darwin の system package、cask、activation を変更する場合は
`nix/hosts/darwin/configuration.nix` を編集し、`default.nix` は import 配線だけに保ちます。
