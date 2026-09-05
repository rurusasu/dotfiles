# Home Manager テスト

## 対象

`nix/tests/home/` は `nix-unit` で Home Manager の構造・import 境界を静的に検査する。
テスト式自身は評価するが、Home Manager モジュールを組み合わせた構成や activation
package の評価は行わない。
システムの activation、実機依存の動作、秘密情報は対象外とする。

## ファイル規則

- ファイル名は `<topic>.nix` の kebab-case とする。
- 1ファイル1責務とし、import 境界・OS 入口・構造検査などの単位で分ける。
- テストは `nix-unit` 形式の attrset とし、属性名は `test` で始める。
- 各テストは `expr` と `expected` を持ち、評価結果を直接比較する。
- テスト内のパスはテストファイルからの相対 Nix path を使う。

## 実行規則

- テストは純粋・決定的に保つ。ネットワーク、secret、環境依存の値、Home Manager activation を使わない。
- 外部コマンドを起動せず、必要な検査は Nix 式で実装する。
- 新しいテストは `nix/flakes/tests.nix` の `perSystem.nix-unit.tests` に登録する。
- `nix flake check` は実行環境の system に対する flake の `checks` 全体を評価する。この README が
  扱う `nix/flakes/tests.nix` から登録される check の保証範囲は、`nix-unit` の構造・import 境界
  検査に限られ、Home Manager 構成、activation package、NixOS/WSL/Darwin の実機動作までは保証しない。
- `nix flake check --all-systems` は flake の `systems.nix` が公開する各 system の `checks` 全体を
  対象にする。この README が扱う check の保証範囲は同じ静的検査に限られる。`--no-build` を付けた
  場合は評価のみで、derivation の build 成功も保証しない。
- テスト変更時は対象テストと `nix flake check` を実行する。

## Home Manager 構成の評価

構成を実際に組み合わせて評価する経路は、`nix-unit` とは別に Bats と CI の build で確認する。

| 対象 | テスト経路 | 確認する内容 |
| --- | --- | --- |
| NixOS / WSL | `tests/bash/flake_outputs.bats` | flake の出力と NixOS-WSL Home Manager 構成を `nix eval` で確認するケースを含む |
| Darwin | `tests/bash/macos_config.bats` | Darwin Home Manager 構成を `nix eval` で確認するケースを含む |
| CI の declarative build | `.github/workflows/ci-bootstrap.yml` | Bats とは別に、Linux/NixOS、NixOS-WSL、Darwin の出力を明示的な `nix build` または WSL switch で確認する |

ローカルでの Bats の標準入口は `task test:bash` であり、全スイートを完走するには Nix が必要である。
一部の Nix 依存ケースは `command -v nix` を確認し、Nix がない環境では `skip` するが、Nix なしで
`task test:bash` 全体を完走できることは意味しない。CI では `.github/workflows/ci-contract.yml` が
`tests/bash/install_linux.bats` と `tests/bash/install_macos.bats` を除外し、それ以外の
`tests/bash/*.bats` を実行する。

上記 Bats ファイルには grep による契約検査も含まれるため、Bats 全体を Home Manager 構成の
完全評価とはみなさない。
