# Home Manager テスト

`nix/tests/` は、Home Manager module、host layout、OS 別の構成を Nix-native に検査する権威あるテスト層です。
構造・import 境界だけでなく、固定した入力で `homeManagerConfiguration` を組み合わせた実効 option、
package、session variable も `nix-unit` で評価します。

## 所有境界

- Nix expression、Home Manager option、package 選択、session variable、flake output は `nix/tests/` に記載する。
- `tests/bash/` は shell/installer の順序、外部コマンドの stub、runtime/integration 契約に限定する。
- Nix 設定の値を `nix eval` で確認するだけの Bats テストは追加しない。値 assertion は
  `nix/tests/` に置く。`package_catalog.bats` に Nix-value/source-shape assertion は残さない。
  `nixos_wsl_postinstall.bats` の `nix eval` は、stubbed `nixos-rebuild` 境界内で選択 user と
  `--impure` 伝播を実 Nix eval で確認するruntime/integration assertionに限る。
- activation、実機のサービス起動、secret、network は Nix-unit の対象外とし、必要な runtime 契約だけを Bats または CI の実機ジョブで検査する。

## ファイル規則

- ファイル名は `<topic>.nix` の kebab-case とする。
- 1ファイル1責務とし、テストは `nix-unit` 形式の attrset にする。
- 属性名は `test` で始め、各テストは `expr` と `expected` を持つ。
- テスト内のパスはテストファイルからの相対 Nix path を使う。
- 新しいテストは `nix/flakes/tests.nix` の `perSystem.nix-unit.tests` に登録する。
- host の entrypoint/configuration の分割は `nix/tests/hosts/` に記載する。

## 実行

```bash
# Nix configuration の authoritative check
nix flake check --all-systems --no-write-lock-file

# 現在の system で nix-unit を実行する焦点確認
nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').nix-unit \
  --no-link --no-write-lock-file
```

`--no-build` は flake graph の評価だけで、nix-unit assertion の実行結果や
derivation の build 成功を保証しません。変更時のローカル必須検証では上記の
`nix flake check --all-systems --no-write-lock-file` と、対象環境での focused build を
両方実行してください。対象 system ごとの focused build は次のとおりです。

```bash
nix build .#checks.x86_64-linux.nix-unit --no-link --no-write-lock-file
nix build .#checks.aarch64-linux.nix-unit --no-link --no-write-lock-file
nix build .#checks.aarch64-darwin.nix-unit --no-link --no-write-lock-file
```

CI で Nix job が route された場合は `x86_64-linux`（`ubuntu-24.04`）で
`nix flake check --no-build` と `nix build .#checks.x86_64-linux.nix-unit --no-link` を、
Darwin job が route された場合は `aarch64-darwin`（`macos-15`）で
`nix build .#checks.aarch64-darwin.nix-unit --no-link` を実行します。
`aarch64-linux` は flake の support/output には含まれますが、この workflow には
ARM64 Linux runner の native build がありません。`aarch64-linux` を focused build する場合は
対応する実行環境または builder を使ってください。
`aarch64-darwin` の結果は `aarch64-linux` の coverage を代替しません。

## Bats の所有境界と完全分類

`tests/bash/package_catalog.bats` は9件で、repository、installer/runtime、CI gate、generated artifact、
署名済みbundleの独自契約だけを含みます。Nix値/source-shape assertionsは移管済みです。
番号は現在の `@test` 出現順です。
CIのexport checkはWinget/npm/pnpm JSON全体を生成してcommitted filesとbyte-for-byte比較するため、
個別metadata grepは重ねません。nix-unit ownership assertionはBats一覧とREADME分類の完全一致を検査します。

### Bats runtime / artifact / repository contracts（9件）

| 番号 | テスト | native suite に残す契約 |
| ---: | --- | --- |
| 1 | `Claude and TablePlus are not managed by dotfiles` | chezmoi / handler / skill tree presence |
| 2 | `DeepSeek Harness remains in chezmoi global pnpm data` | chezmoi pnpm source data |
| 3 | `DeepSeek Harness native builds are pre-approved for pnpm global installs` | rendered installer behavior on Linux/macOS |
| 4 | `DeepSeek Harness is reinstalled when the native build approval changes` | installer decision/runtime behavior |
| 5 | `pnpm v11 global installs skip packages present in the global manifest` | pnpm runtime skip behavior |
| 6 | `CI consistency workflow gates on package provider coverage` | distinct consistency-workflow gate wiring; named output/derivation linkage is evaluated by `ownership.nix` |
| 7 | `winget export reproduces committed Windows manifests byte-for-byte` | complete generated Winget/npm/pnpm artifacts |
| 8 | `Darwin Raycast artifact has the declared identity and trusted signature` | built app identity, codesign, Gatekeeper |
| 9 | `Darwin Discord keeps staged modules outside its signed application bundle` | built layout, launcher path, app identity and signatures |

### PR #633 nix-unit 移行台帳

Registry/README/ownership integration owner: manager. Module implementation owners are the contributing workers; completed suite audits and exact mappings are recorded below. After the catalog source-shape cleanup, the four focused Pester files contain 162 It cases; the post-cleanup run passed 162/162 with no skips. The CI export contract generates Winget/npm/pnpm JSON and byte-compares each complete committed file, so per-package generated metadata greps are not kept as duplicate Bats checks.

| Owner / source assertion | nix-unit owner / review | disposition |
| --- | --- | --- |
| Manager · package_catalog.bats #1–9 | 41 package-catalog modules registered once | All nine remaining cases are repository/runtime/CI/artifact contracts. Hermes cask and launcher, Dia candidate, Darwin promotions, ChatGPT platform selection, and Winget helper spelling are evaluated by registered nix-unit modules; Discord ID membership is covered by complete manifest equality and catalog ownership, so its duplicate grep was removed. |
| Manager · removed Pester `should expose explicit feature-aware resolver and provider metadata contracts` | `chatgpt-linux.nix::testChatGPTPackageSelectionRemainsHostDependent`; `package-catalog-validation-fixtures.nix::testPackageCatalogValidationFixtures` (`missingSource`, `missingIdentity`, `nixProviderCannotIncludeCask`, `activeDerivationMustSupportHost`, `duplicateNixAndHomebrewResolution`); `package-catalog-windows-only-support.nix::testPowerToysSupportMetadata`; `package-catalog-wsl.nix::testMicrosoftWslHasWindowsOnlyWingetSupport`; `package-catalog-msstore.nix::testCodexDesktopIsWindowsOnlyMicrosoftStorePackage` | Independent read-only audit mapped all seven regexes to evaluated resolver behavior, validation error values, and Windows-only provider outputs. No Pester-only runtime/artifact contract; removed. Former Nix-eval fixture skip also removed. |
| Kepler + manager · Pester source/value assertions | Completed audit; registered catalog, PATH, verifier, feature, retired-ID, Home Manager, and Darwin-selection modules reviewed | Removed Nix-source greps for resolver/provider metadata, WezTerm policy, gwq, exporter spelling, Herdr/Warp, NRS aliases, WSL verifier, PATH/package roots/portable links, Codex Desktop verifier/CI skip, netcat, agent-browser, rust-analyzer, ChatGPT providers, PowerToys verifier identity, Arc/Windows Terminal verifier values, Windows-only membership, and Docker provider wiring. Raycast/Dia exact Winget manifest absences, retired-ID absence across generated manifests, other generated verifier/artifact values, WSL runtime recovery, Taskfile/update wiring, and all-entry verifier behavior remain. NRS aliases are evaluated in `home/composition.nix::testNRShellAliasUsesPlatformInstallCommand`. |
| Python audit · `test_registry_has_only_explicit_reviewed_candidates` | `darwin-provider-candidates.nix::testDarwinProviderCandidateRegistry` registered exactly once; Nash's scoped rewrite is complete | Live production candidate keys/values are owned by nix-unit. Python tests `load_candidate_registry` with a temporary fixture covering null, explicit `nixAttr`, and an empty candidate list; focused unittest passed. Updater behavior tests remain in Python. |
| Rawls · `linux_config.bats` (2), `taskfile_test_routing.bats` (10), `tart_dotfiles_sync.bats` (11) | `system-manager-integrations.nix`, `home/rebuild-aliases.nix`, and existing host/composition modules registered | Seven Nix-value assertions moved: Home Manager import and `nix.enable`, Ollama bind configuration, `nrt`, `nrb`, and Tart selected package/output. Remaining Bats cases retain Taskfile sequencing/update wiring, Docker Compose host-gateway and Ollama runtime, plus Tart guest synchronization/runtime. |
| Raman · `tart_vm_installer.bats` (8) | `package-catalog-tart-minimal.nix::testTartCatalogUsesResolvedNixPackageAndRetainsDarwinMigrationMetadata` registered | Provider/source/nixAttr/identity/command/legacyDarwin values are evaluated; removed only the metadata source-shape case. All eight remaining installer/VM/Taskfile cases remain. |
| Gauss · `linux_config.bats` (2) | `system-manager-host-contracts`, `system-manager-docker-config`, `system-manager-user-identity`, `system-manager-integrations`, and `home/composition.nix` | Evaluated Ubuntu/Debian outputs, lock follows, gh wiring, configured identity, Docker service/socket, Ollama bind values, and HM platform aliases. The two remaining Bats cases retain distinct Taskfile sequence and Ollama Compose/runtime assertions. |
| Gauss · install_linux.bats (14 cases) | System Manager host/config facts overlap only | Preserve all installer/runtime/process/environment/ID-routing assertions, sequencing, `switch --flake .#debian`, installer wiring and invalid-user rejection. |
| Wegener · install_macos.bats (64 cases) | No nix-unit owner | All are installer/runtime/filesystem/security/command-order/artifact/CI contracts. Resulting profile values do not duplicate installer behavior; preserve all 64. |
| Completed independent audit domains · Python/CI; Bash config/task/CI; Lua, Docker, remaining shell | Python reviewed candidate registry; Rawls/Gauss reviewed Linux config, Taskfile routing, and Tart sync; Raman/Wegener reviewed installer suites and Tart VM installer | Python's live candidate values moved to nix-unit while fixture parser/updater behavior remains. Seven Linux/Home Manager/System Manager/rebuild-alias/Tart output value assertions moved; sequencing, update wiring, Compose/runtime, guest sync, and VM installer behavior remain. All 14 `install_linux.bats` and 64 `install_macos.bats` cases remain runtime/installer contracts. Current counts are enforced for linux_config (2), taskfile routing (10), Tart sync (11), and Tart VM installer (8). |
| Manager · Home Manager WSL package/Tart output | `home/composition.nix`, `package-catalog-tart-minimal.nix` registered | WSL evaluates effective `home.packages`; Tart evaluates minimal list and output drvPath. Guest sync/runtime remains Bats. |
| Fermat · `flake-outputs.nix` (8 legacy groups, 10 current assertions) | Registered once, reviewed | Omitted-default environment paths and explicit user/hardware/system overrides are evaluated; `nixosSystem` remains a constructor stub and names now describe wiring specs. No full NixOS module-graph claim. |
| Hostile reviews · Nix ownership/assertions and Bats/Pester boundaries | No actionable boundary findings; the one ChatGPT naming P2 was fixed | No unique Bats/Pester runtime/artifact behavior was lost and every moved Nix config assertion has an evaluated owner. ChatGPT install-phase assertion is explicitly named as an install-phase string contract, not a package build or filesystem-layout test. README does not key ownership to that test attribute name. |
| Registry / dedicated checks | 62 recursive nix-unit modules, 62 unique imports, 144 unique `testX`-prefixed attributes across all 65 files (including the bootstrap VM's `testScript`); 41 package-catalog and 4 System Manager modules; 6 nested modules | Excludes only `neovim.nix` and `bootstrap-nixos.nix` (package checks) and `hardware-configuration.nix` (bootstrap VM fixture). Nested `home/rebuild-aliases.nix` is included; System Manager exact-owner list includes docker-config, host-contracts, integrations, and user-identity. `ownership.nix` derives recursive inventory, exact-once registration, and unique test-prefixed attribute names. Counts were independently statically checked; CI must execute nix-unit assertions. |

`tests/bash/tart_vm_installer.bats` now has eight cases: the explicit Tart VM preparation Taskfile contract, existing-VM no-op, insufficient-space rejection, overflow rejection, decimal parsing for leading-zero capacities (including digit eight), configured image cloning into `TART_HOME`, and reserved VM-name rejection. These remain because they exercise installer/runtime behavior, not catalog values.
必須検証は、Nix の authoritative check（`nix flake check --all-systems --no-write-lock-file` と
focused `nix-unit` build）に加えて `task test:bash`、または変更対象に絞った `bats` 実行を行うこと。
package catalog の変更時は focused exact command として `bats tests/bash/package_catalog.bats` も実行する。
Nix または `jq` がないため Bats ケースが `skip` された場合、検証成功とは扱わない。必要なツールを
用意して再実行するか、未検証として停止する。
