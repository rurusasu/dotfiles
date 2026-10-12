# Markdown フォーマット設定 (dprint)

Markdown の自動整形は [dprint](https://dprint.dev/) が担当します。
`nix fmt`・`task fmt`・pre-commit・CI の対象です。
設定は [nix/formatter.nix](../../nix/formatter.nix) の `treefmt.programs.dprint` に宣言します。

```nix
dprint = {
  enable = true;
  includes = [ "*.md" ];
  settings = {
    lineWidth = 100;
    markdown = {
      lineWidth = 100;
      textWrap = "maintain";
      emphasisKind = "asterisks";
      strongKind = "asterisks";
      newLineKind = "lf";
    };
    plugins = pkgs.dprint-plugins.getPluginList (plugins: [ plugins.dprint-plugin-markdown ]);
  };
};
```

treefmt-nix が JSON 設定を Nix store に生成し、dprint に `--config` で渡します。
Markdown プラグインも nixpkgs の依存として取得するため、整形中のダウンロードは不要です。
プラグインのバージョンは `flake.lock` の nixpkgs に従います。
oxfmt の対象は JSON/YAML に限定し、Markdown を二重整形しません。

## 設定値

| オプション     | 値            | 説明                       |
| -------------- | ------------- | -------------------------- |
| `lineWidth`    | `100`         | 行幅の目安                 |
| `textWrap`     | `"maintain"`  | 既存の文章の折り返しを維持 |
| `emphasisKind` | `"asterisks"` | 強調に `*` を使用          |
| `strongKind`   | `"asterisks"` | 太字に `**` を使用         |
| `newLineKind`  | `"lf"`        | LF で保存                  |

## 実行

```bash
nix fmt -- README.md
nix fmt -- --fail-on-change README.md
```

エディターから同じ設定を使う場合は [treefmt のエディター連携](treefmt.md#エディター) を参照してください。
dprint を直接起動する拡張機能は、Nix store の設定を自動では読みません。

## 参照

- [treefmt-nix dprint module](https://github.com/numtide/treefmt-nix/blob/main/programs/dprint.nix)
- [Markdown プラグイン設定](https://dprint.dev/plugins/markdown/config/)
