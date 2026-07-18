# gwq nixpkgs 移行設計

## 目的

公開 OSS である `gwq` のローカル Nix derivation を廃止し、nixpkgs が提供する `pkgs.gwq` を全 Unix 系環境で利用する。Windows は `gwq` が Unix 向け CLI のため、winget 管理対象には追加しない。

## 現状

- `nix/packages/sets.nix` の `gwq` entry は `nix/packages/gwq/default.nix` を import している。
- `flake.nix` の `gwq-src` input と、各 package set の `gwqSrc` 引き渡しで GitHub source を供給している。
- Linux/NixOS/WSL と macOS は Nix provider を使う。
- Windows は `winget = null` で、reviewed unsupported reason により provider coverage を満たしている。
- 現在の nixpkgs lock revision では `pkgs.gwq` が利用できないが、対象の `nixos-unstable` には `gwq` が登録されている。

## 設計

### Nix provider

`sets.nix` の entry を次の形へ変更する。

```nix
gwq = {
  pkg = pkgs.gwq;
  winget = null;
  category = "dev";
};
```

`flake.lock` は `nixpkgs` を更新して、`pkgs.gwq` を含む revision を固定する。これに伴う他の nixpkgs package 更新は許容する。

### 不要なローカル定義の削除

次を削除する。

- `flake.nix` の `gwq-src` input
- `nix/packages/gwq/default.nix`
- `sets.nix`、`nix/flakes/packages.nix`、`nix/home/common.nix`、`nix/darwin/default.nix`、`nix/modules/host/default.nix`、`nix/packages/winget.nix`、`nix/packages/support-report.nix` にある `gwqSrc` 引数・引き渡し

### OS 別 provider

- Linux / NixOS / WSL: `pkgs.gwq` を Home Manager または system package set 経由で導入する。
- macOS: `pkgs.gwq` を Home Manager 経由で導入する。
- Windows: winget manifest には追加しない。既存の `winget = null` と `reviewedUnsupported.windows.gwq` を維持する。

### テストと生成物

- `scripts/powershell/tests/PackageCatalog.Tests.ps1` の `gwq-src`・ローカル derivation 前提を、`pkgs.gwq` と Windows unsupported provider 前提へ更新する。
- Nix 評価で `pkgs.gwq` が存在すること、catalog の provider error が空であることを確認する。
- `gwq` は Windows manifest に出力されないことを確認する。
- `flake.lock` 更新後、既存の生成 manifest に不要な `gwq` Windows entry が発生しないことを確認する。

## 採用理由

ローカル fallback や overlay は、nixpkgs に正式登録された package と二重管理になるため採用しない。nixpkgs の recipe、依存関係、プラットフォーム metadata、更新追従を一元利用する。

## 非対象

- Windows で `gwq` を別 installer（winget、npm、手動 zip）から提供すること。
- `gwq` 以外の package provider や OS 別 package policy の整理。
- nixpkgs 更新に伴う個別 package の意図的な version pinning。
