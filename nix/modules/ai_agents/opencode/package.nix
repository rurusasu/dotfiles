{ pkgs }:
# nixpkgs 1d06008 の opencode 2.2.5 は bun 1.4.4 の libc filter で
# fixed-output hash が Linux と Darwin で変わる。--libc="*" で共通化する。
# 上流修正が入ったら削除する: https://github.com/NixOS/nixpkgs/issues/582673

if pkgs.opencode.version == "2.2.5" then
  pkgs.opencode.overrideAttrs (previous: {
    node_modules = previous.node_modules.overrideAttrs (nodeModules: {
      buildPhase =
        builtins.replaceStrings [ "--ignore-scripts" ] [ ''--ignore-scripts --libc="*"'' ]
          nodeModules.buildPhase;
      outputHash = "sha256-dIveiaiPFGSItwLyeMuPDxTE9gpvvnlTCB/+nG24qCc=";
    });
  })
else
  pkgs.opencode
