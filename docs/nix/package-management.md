# パッケージ管理

## Single Source of Truth

`nix/packages/sets.nix` の catalog が全プラットフォームの package provider を一元管理します。Home Manager だけを SSOT とするのではなく、1 つの catalog から OS ごとの実装を導出します。

| Catalog output        | Consumer                            | Platform                     |
| --------------------- | ----------------------------------- | ---------------------------- |
| `all` / category sets | `nix/home/common.nix`               | macOS、NixOS、Ubuntu、Debian |
| `darwinCasks`         | nix-homebrew in nix-darwin          | macOS                        |
| `linuxSystemModules`  | NixOS / System Manager modules      | Linux                        |
| `wingetMap`, `npmMap` | `nix/packages/winget.nix`           | Windows                      |
| `supportReport`       | `package-support-report` derivation | CI and review                |
| `providerErrors`      | flake check                         | all platforms                |

Windows だけに存在する GUI や OS component は `windowsOnlySupport` に置き、macOS/Linux で対応しない理由を必ず記録します。クロスプラットフォームのツールを理由なしに Windows-only へ入れることはできません。

## Provider の追加

一般的な CLI は catalog に Nix package と Windows provider を記述します。実際の schema は既存 entry に合わせてください。

```nix
mypackage = {
  package = pkgs.mypackage;
  category = "dev";
  windows = {
    provider = "winget";
    id = "Publisher.Package";
  };
};
```

macOS cask や Linux system module が必要な application は、それぞれの provider metadata も同じ entry に追加します。どの OS にも provider がない場合は、その OS の `unsupported` reason が必要です。

## OS ごとの反映

通常は個別コマンドではなく one-command installer を再実行します。

```text
Windows:          install.cmd
macOS:            ./install.sh
NixOS:            ./install.sh
Ubuntu / Debian:  ./install.sh
```

- Windows は catalog から生成された winget/npm/pnpm manifest を PowerShell handlers が適用します。
- macOS は nix-darwin が Home Manager と nix-homebrew cask を同じ switch に含めます。
- Ubuntu/Debian は System Manager が Home Manager と system package/service を適用します。
- NixOS は NixOS generation に Home Manager と system module を統合します。

その他 Linux の `DOTFILES_ALLOW_USER_ONLY=1 ./install.sh` は Home Manager のみで、Docker や OS service は管理しません。

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

`package-support-report` は各 catalog entry の Windows、Darwin、Linux provider または unsupported reason を記録します。自動推測できない provider gap は `reviewedUnsupported` に package 名と理由を明示し、新規 entry の未検討 platform は `checks.*.package-provider-coverage` で失敗させます。consistency CI は生成 manifest drift も失敗にします。

## システム package と Home Manager の境界

| 対象                                             | 管理先                              |
| ------------------------------------------------ | ----------------------------------- |
| shell から使う共通 CLI                           | Home Manager `home.packages`        |
| Docker daemon/socket、ユーザー group、OS service | NixOS / System Manager / nix-darwin |
| macOS GUI application                            | nix-homebrew cask                   |
| Windows GUI/OS application                       | winget/msstore handler              |
| shell、Git、terminal、editor 設定                | chezmoi                             |

同じ package を Home Manager と system layer の両方へ重複させるのは、system service が絶対 path を必要とする場合に限定します。

## 主なファイル

| File                              | Responsibility                           |
| --------------------------------- | ---------------------------------------- |
| `nix/packages/sets.nix`           | provider catalog and derived sets        |
| `nix/packages/support-report.nix` | coverage report derivation               |
| `nix/packages/winget.nix`         | generated Windows manifests              |
| `nix/home/common.nix`             | shared Home Manager packages             |
| `nix/darwin/default.nix`          | macOS system and casks                   |
| `nix/system-manager/`             | Ubuntu/Debian system packages and Docker |
| `nix/hosts/linux/`                | native NixOS system packages and Docker  |
| `nix/flakes/packages.nix`         | package sets, report, and checks         |
