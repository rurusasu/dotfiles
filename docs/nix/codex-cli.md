# Codex CLI の Nix パッケージ方針

## 採用方式

NixOS、WSL、Apple Silicon macOS の Codex CLI は、`pkgs.codex` ではなく
`llm-agents.nix` の `codex` package を使用する。

```nix
inputs."llm-agents".packages.${system}.codex
```

この package は OpenAI Codex の Rust release tag を source とし、version、source
hash、Cargo hash、`rusty_v8` の platform 別 hash を lock 管理する。Numtide の CI は
package を日次更新し、対応 system はこの repository の Nix 対象と一致する。

Windows は Nix package の対象外であり、引き続き `OpenAI.Codex` winget package を
使用する。したがって Nix input の更新だけでは Windows の Codex version は更新されない。

package catalog の provider metadata も、Nix 側を `llm-agents.nix`、Windows 側を
`winget` として明示する。これにより support report が Codex の実体を `nixpkgs/codex`
と誤認せず、macOS の `codex --version` 検証も同じ derivation に対して実行される。

## 更新方法

`nix flake update` は flake input を更新するだけで、Nixpkgs package の
`passthru.updateScript` を実行しない。`task nrs`、`install.sh`、およびそれらが呼び出す
update 経路は flake input を更新するため、そのとき lock された `llm-agents` revision が
更新される。一方、既存の lock を参照するだけの `nix profile upgrade` や Home Manager
activation 単独では upstream の最新 revision は取得しない。手動で Codex input だけを
更新する場合は次を実行する。

```bash
nix flake update llm-agents
nix eval --raw .#packages.x86_64-linux.codex.version
nix eval --raw .#packages.aarch64-linux.codex.version
nix eval --raw .#packages.aarch64-darwin.codex.version
```

更新後は通常の Nix profile/Home Manager activation で Codex を再構築する。

## 比較した方式

| 方式                                     | 採否     | 理由                                                                                           |
| ---------------------------------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `pkgs.codex`                             | 不採用   | Nixpkgs の package 更新 cadence に version が拘束される                                        |
| `llm-agents.nix`                         | 採用     | 公開済みの Codex derivation、日次更新、固定 hash、対象 system の一致                           |
| OpenAI `codex-package` の自前 `fetchurl` | fallback | 公式 archive と target/hash の管理を repository が直接引き受ける必要がある                     |
| npm package の直接利用                   | 不採用   | Node launcher と platform optional dependency を含み、Nix の native CLI package と責務が異なる |

`llm-agents.nix` の package は公式 npm package 全体ではなく、同じ OpenAI Codex
Rust CLI を Nix で再現するものとして扱う。npm package と byte-for-byte 同一である
ことを未検証の platform まで主張してはいけない。

## 供給網と cache

この flake は `llm-agents.nix` の input revision と各 hash を lock する。Numtide binary
cache を利用する場合は、repository またはホストの Nix 設定に trusted substituter/key を
追加する判断が別途必要になる。この repository は cache を暗黙に信頼せず、設定しない
環境では同じ固定 source からローカル build できる。`follows = "nixpkgs"` は cache hit と
互換性を損なう可能性があるため設定しない。

## 検証

最低限、次を確認する。

```bash
nix flake check --no-build --all-systems
nix eval --raw .#packages.x86_64-linux.codex.version
nix eval --raw .#packages.aarch64-linux.codex.version
nix eval --raw .#packages.aarch64-darwin.codex.version
nix build .#codex --no-link
```

Windows 側は既存の winget/Pester 検証と `codex --version` を実行する。

CI の実ビルドは GitHub-hosted Ubuntu の `x86_64-linux` で実行し、
`--all-systems` の flake check で `aarch64-linux` と `aarch64-darwin` の出力評価を行う。
ARM/Linux と macOS の native build は upstream の対象 system 別 binary cache または各環境の
native builder を利用して確認する。CI の Ubuntu job がそれらの native build 成功を保証する
ものではない。

## Evidence snapshot

2026-09-06 に次の scope で再検証した。

- 検索語: `Nixpkgs Codex package`, `llm-agents.nix Codex`, `OpenAI Codex release Nix`,
  `nix flake update updateScript`
- [Nixpkgs の Codex 定義](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/co/codex/package.nix)
- [Numtide の llm-agents.nix README](https://github.com/numtide/llm-agents.nix)
- [Numtide の Codex derivation](https://raw.githubusercontent.com/numtide/llm-agents.nix/main/packages/codex/package.nix)
- [OpenAI の公式 release manifest](https://releases.openai.com/codex/channels/latest)
- [Nix の `nix flake update` マニュアル](https://nix.dev/manual/nix/2.31/command-ref/new-cli/nix3-flake-update.html)

ローカルの実測では、固定した `llm-agents` input の Codex version は対象3 system
すべてで `0.153.4` だった。Nixpkgs の `passthru.updateScript` は存在しても、通常の
`nix flake update` からは呼ばれない。過去に比較した macOS ARM と Linux x64/musl
では npm optional dependency の native binary と公式 archive の `bin/codex` が一致した
（macOS ARM: `b973d440acac501fd2594a43e7ca9ce41e0a65b9dfb28d0d7a7837c99e1261e3`、Linux
x64/musl: `56ef98ab4032d317ab26e9b5e5a175650717351edb16ed9cde0cb6d1734d62da`）。この比較は
それら2 target の version `0.153.4` に限った実測であり、未検証の platform まで同一性を
拡張しない。
