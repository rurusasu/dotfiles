# nix/modules: アプリと連携の所有範囲

- アプリの package・有効化・設定・専用の実行依存は、そのアプリの `default.nix` が所有する。原則として module 内で `programs.<name>.enable = true` とし、対応しない OS の判定も module 内に置く。
- `home/` と `hosts/` にアプリの enable 一覧や package list を作らない。module のないアプリを追加導入しない。
- Home Manager module は `modules/default.nix` の imports に明示する。アプリ内の子 module も親で明示的に import する。自動検出・registry・callback は使わない。
- NixOS / nix-darwin 用の設定は必要な場合だけ同じアプリ直下の `nixos.nix` / `darwin.nix` に分け、対応する hosts から import する。module 内に OS 名のディレクトリは作らない。
- 純粋な package factory・renderer は通常の関数にし、Home Manager module の imports に渡さない。`formatters/default.nix` は flake-parts 用、`formatters/treefmt.nix` は treefmt-nix 用で、Home Manager には import しない。
- Unix のパッケージは共通 nixpkgs の標準 package を優先する。追加 flake・公式配布物を使う例外は `docs/nix/package-management.md` に理由を書く。
- Steam の macOS bootstrap は公式 DMG の Nix package、Google Drive は公式 DMG と PKG 適用を Nix が管理する。Homebrew は使わない。
- Hermes は同梱 Python、各 module の内部依存はその module が管理する。Neovim の LSP・整形ツール・toolchain・プラグイン実行依存は Neovim module が所有する。
- 共通のキー配列は `home/keybindings/bindings.nix`。各アプリの設定生成はそのアプリが所有する。アプリを外したら、残る Dock・shortcut・credential helper の依存も整理する。
- Unix の設定は Home Manager の標準 option と `xdg.configFile` が所有する。Windows の設定と WinGet manifest は `chezmoi/` が所有し、二重配布しない。
- stateVersion は root `flake.nix`、ユーザー情報は `home/settings.nix`、Nix ポリシーは `modules/nix/settings.nix` が所有する。
- 変更・レビュー時は minimal-tests を適用する。Nix 値は `tests/unit/`、実行契約は `tests/build/`、共有入力は `tests/fixtures/` に置く。
