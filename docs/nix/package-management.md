# パッケージ管理

## Single Source of Truth

`nix/packages/catalog/` が全プラットフォームの package と provider metadata の正本です。`nix/packages/sets.nix` は catalog、provider 選択、installer metadata を合成する公開入口であり、既存の consumer は引き続きこの入口を import します。

## 分割の理由と編集先

SSOT は「各定義を一度だけ持つ」ことであり、すべてを 1 ファイルに置くことではありません。変更理由の異なる package データ、provider 選択、配布 metadata、host の動作を分け、パッケージ追加が OS 設定や選択ロジックの変更に広がらない構成にします。

| 編集先                                                                           | 責務・分割理由                                                                                      |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `catalog/{core,dev,terminal,editors,fonts,llm,desktop,system,k8s,infra,lsp}.nix` | カテゴリごとの package と OS 別 provider metadata。各 package は 1 ファイルだけで定義する           |
| `catalog/context.nix`                                                            | カテゴリ間で共有する package 構築用の依存値                                                         |
| `catalog/default.nix`, `catalog/merge.nix`                                       | カテゴリの合成と重複定義の検出。後勝ちで上書きしない                                                |
| `providers/{common,normalize,selection,validation}.nix`                          | provider の共通処理、正規化、OS 別選択、coverage 検証。package データから分離する                   |
| `install/{default,node,windows-install,windows-verification,windows-only}.nix`   | npm/pnpm 配布、Windows install/検証/専用アプリの metadata。provider 選択と installer 契約を区別する |
| `sets.nix`                                                                       | 上記を合成し、従来の export API を維持する小さい入口                                                |
| `<package>/default.nix`                                                          | custom derivation。既存パスを保ち、catalog から参照する                                             |
| `nix/home/keybindings/`                                                          | 共通キー配置・設定生成・ユーザー設定。パッケージの配布定義へ混在させない                            |
| `nix/hosts/`                                                                     | OS の service/有効化・競合解除。home 側の設定を消費し、キー配置を複製しない                         |

ディレクトリはすべて `nix/packages/` 相対です（表内で `nix/` から始まる行を除く）。カテゴリは探索と編集の単位であり、OS ごとに同じ package を再定義しません。[共通のキー割り当て](../chezmoi/omarchy.md) も同じ考え方で home に一度だけ定義し、host module は OS 統合と有効化を担当する構成です。

native desktop 用 package は `catalog/native-desktop.nix` に定義します。`sets.all` は全 feature を含むため、`installFeature` を付けるだけでは WSL/standalone への非混入を保証できません。`sets.nativeDesktopPackageNames` を使い headless Home Manager consumer で除外し、native host と選択された home module のみが `WithDesktop` で解決します。

| Catalog output                      | Consumer                            | Platform                     |
| ----------------------------------- | ----------------------------------- | ---------------------------- |
| `all` / category sets               | `nix/home/common.nix`               | macOS、NixOS、Ubuntu、Debian |
| `darwinCasksForInstallFeatures`     | nix-homebrew in nix-darwin          | macOS                        |
| `linuxSystemModules`                | NixOS / System Manager modules      | Linux                        |
| `wingetMap`, `npmMap`, `pnpmGlobal` | `nix/packages/winget.nix`           | Windows                      |
| `supportReport`                     | `package-support-report` derivation | CI and review                |
| `providerErrors`                    | flake check                         | all platforms                |

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

macOS の `nrs` は nix-darwin を通じて Nix/Home Manager と宣言済み Homebrew provider を反映します。通常の CLI と Neovim・WezTerm は Nix 側で管理し、cask/formula は catalog が明示する例外です。Nix パッケージの版は `flake.lock` に従います。

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

Neovim は `nix/packages/neovim/default.nix` でパーサーと対応クエリを同梱します。設定と対象言語は [Neovim の運用](../chezmoi/neovim.md) を参照してください。pnpm 配布の LSP は `pnpmGlobal` と `support.windows` の `provider = "pnpm"` / `source = "npm"` / `identity` を合わせて宣言します。

## 主なファイル

| File                                 | Responsibility                           |
| ------------------------------------ | ---------------------------------------- |
| `nix/packages/catalog/`              | package と provider metadata の正本      |
| `nix/packages/providers/`            | provider 選択、正規化、coverage 検証     |
| `nix/packages/install/`              | installer と manifest 用 metadata        |
| `nix/packages/sets.nix`              | 合成と既存 consumer 向けの公開 API       |
| `nix/packages/support-report.nix`    | coverage report derivation               |
| `nix/packages/winget.nix`            | generated Windows manifests              |
| `nix/home/common.nix`                | shared Home Manager packages             |
| `nix/hosts/darwin/configuration.nix` | macOS system and casks                   |
| `nix/system-manager/`                | Ubuntu/Debian system packages and Docker |
| `nix/hosts/linux/`                   | native NixOS system packages and Docker  |
| `nix/flakes/packages.nix`            | package sets, report, and checks         |

各 host は `nix/hosts/<host>/default.nix` を entrypoint、`configuration.nix` を実体とする分割を
標準とします。Darwin の system package、cask、activation を変更する場合は
`nix/hosts/darwin/configuration.nix` を編集し、`default.nix` は import 配線だけに保ちます。
