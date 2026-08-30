# Task 7 Report: Migrate Discord while preserving WithHermes

## Status

`PASS` — the Hermes-only Nix Discord migration is active and verified. The
user LaunchAgent restaged modules across two exact GUI launches and the formal
launch verifier. The former Homebrew cask was removed with a normal uninstall;
no `--zap` operation was used, and user Discord data was preserved.

## Changed files

- `nix/packages/sets.nix` — Darwin uses a `pkgs.discord.overrideAttrs` result
  which keeps the signed app untouched: nixpkgs-injected modules move to
  `$out/share/discord/modules`, the external `Discord` wrapper stages from
  that location, and `dontFixup = true` prevents later bundle mutation. Linux
  remains direct `pkgs.discord`. Darwin provider metadata remains
  `nix`/`nixpkgs`/`discord`, carries the required GUI identity, and retains
  Homebrew `discord` as `legacyDarwin`; `WithHermes` is unchanged.
- `nix/hosts/darwin/default.nix` — references the catalog-exported Darwin
  Discord derivation in the Hermes-only `postActivation` script, preserving
  actual-user disable-updates and initial module staging. It additionally
  declares `launchd.user.agents.discord-module-staging`; its `RunAtLoad` and
  `KeepAlive.PathState = false` rerun inherited `stageModules` only while the
  version-derived user `installed.json` is absent.
- `tests/bash/package_catalog.bats` — evaluates the Discord support report to
  preserve the Windows/Linux contract and assert the Darwin Nix identity and
  legacy cask metadata; realizes the Darwin artifact and verifies its signed
  app, external module directory, and wrapper staging path.
- `tests/bash/macos_config.bats` — evaluates default and Hermes placement:
  Discord is absent by default and, with Hermes, is a nix-darwin system
  package only (not a cask or Darwin Home Manager package). It also evaluates
  the user LaunchAgent service configuration, including the current
  `installed.json` PathState and external module source; the default profile
  has no such agent.

## TDD evidence

### Migration RED/GREEN

1. The initial provider/placement tests produced 58 passed and 2 failed: the
   catalog still declared the Darwin Homebrew cask and the Hermes profile did
   not install Discord through `environment.systemPackages`.
2. After the provider migration, `nix fmt -- nix/packages/sets.nix` and
   `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats` passed
   60/60.

### Signed-artifact RED/GREEN

1. The strict formal verifier then showed that direct `pkgs.discord` had
   `Contents/Resources/modules` added after vendor signing. A new artifact
   test was added first; it failed as expected with 60 passed and 1 failed at
   the app-bundle modules assertion.
2. The Darwin-only override moved modules outside the app bundle and updated
   only the external wrapper. The focused suite is now 61 passed, 0 failed.

### Activation-wiring RED/GREEN

1. A default/Hermes activation contract first failed because no Discord
   activation script existed. The initial arbitrary script key then evaluated
   but did not appear in nix-darwin's executable `activate` script.
2. The test was changed to inspect the actual generated activation script and
   failed again at the missing user-context command. The implementation now
   uses supported `postActivation`; focused Bats passes 62/62. Default output
   contains no Discord processing, while Hermes includes `launchctl asuser`,
   `sudo --user=... --set-home`, both passthru helpers, and the external
   modules path.

### Restart-staging LaunchAgent RED/GREEN

1. The new evaluated-profile test first ran against the implementation without
   an agent: `bats tests/bash/macos_config.bats` produced 30 passed and 1
   failed at the missing Hermes
   `config.launchd.user.agents.discord-module-staging` service configuration.
2. The supported `launchd.user.agents` declaration now uses `RunAtLoad`,
   `KeepAlive.PathState` with a false value, the inherited stage helper, and
   `${discordPackage}/share/discord/modules`. Its watched filename is derived
   from `${discordPackage.version}`, avoiding a stale version watcher on a
   package update. The focused Bats suite passes 31/31.

## Build, verifier, and regression evidence

```bash
NIX_CONFIG='eval-cache = false' nix build --no-link --print-out-paths .#darwin-discord
NIX_CONFIG='eval-cache = false' nix build --no-link --print-out-paths .#package-support-report
task darwin:verify -- \
  --support-json /nix/store/1vj7cl4jqnz29pp90w0y8l267jmi5y6f-package-support-report/support.json \
  --id discord \
  --store-path /nix/store/pris6y62jfs265ffibd7883ndvpk0ffc-discord-0.0.408
```

- Realized Darwin store path:
  `/nix/store/pris6y62jfs265ffibd7883ndvpk0ffc-discord-0.0.408`.
- Hermes test-user toplevel build:
  `/nix/store/7ihrlp2x5k3sqb29q4hl9p1ykvxf4cfk-darwin-system-26.11.4cff07d`.
  Its executable `activate` contains the expected user-context helpers.
- Hermes actual-user toplevel build:
  `/nix/store/c5cj275qhrj6867kyl7dm38m7ppnpycr-darwin-system-26.11.4cff07d`.
  It is evaluated with `DOTFILES_USER=ktome1995` and
  `DOTFILES_HOME=/Users/ktome1995`; `Applications/Discord.app` exists and the
  generated `activate` invokes the helpers as that exact user. Its generated
  `user/Library/LaunchAgents/org.nixos.discord-module-staging.plist` has
  `RunAtLoad=true`, `KeepAlive.PathState` of
  `/Users/ktome1995/Library/Application Support/discord/0.0.408/modules/installed.json=false`,
  and ProgramArguments for
  `/nix/store/l7w68wv9hi17fc18abz3y1qmc36yka1f-discord-stage-modules` plus
  `/nix/store/pris6y62jfs265ffibd7883ndvpk0ffc-discord-0.0.408/share/discord/modules`.
  It was activated successfully and exposes Discord as
  `/Applications/Nix Apps/Discord.app` with the plist in the actual user's
  `~/Library/LaunchAgents`.
- The no-launch formal verifier passed: expected `Discord.app`, bundle ID
  `com.hnc.Discord`, executable `Discord`, `codesign --verify --deep --strict`,
  and `spctl --assess --type execute` all succeeded.
- `Contents/Resources/modules` is absent from the signed app. The modules are
  present in `$out/share/discord/modules`; `$out/bin/Discord` stages from that
  exact path.
- The realized derivation
  `/nix/store/0lvrk9h3kp0xvprpj7bis19rd5h3wrns-discord-0.0.408.drv` has
  `dontFixup=1` and the expected `postInstall` move/substitution commands.
- Support report:
  `/nix/store/1vj7cl4jqnz29pp90w0y8l267jmi5y6f-package-support-report`, with
  `errors.json = []`.
- Focused Bats: `package_catalog.bats` plus `macos_config.bats`, 63 passed,
  0 failed; the latter was rerun after formatting, 31 passed, 0 failed.
- Pester `PackageCatalog.Tests.ps1`: 49 passed, 0 failed.
- Linux `x86_64-linux` evaluation with the Workmux overlay reports direct
  `pkgs.discord` at
  `/nix/store/vxx22hmmjmxrf0jyrnh8qhpw0gqbp1k1-discord-1.0.154.drv` and
  `providerErrors=[]`; Windows has exactly one `Discord.Discord` Winget entry
  with `installFeature = "WithHermes"`.
- `git diff --check`: no diagnostics.

## Profile and cross-platform contract evaluation

- Default Darwin: Discord `casks=false`, `system=false`, `home=false`.
- `DOTFILES_WITH_HERMES=1`: Discord `casks=false`, `system=true`,
  `home=false`.
- Linux `x86_64-linux` (with the repository Workmux overlay): direct
  `pkgs.discord` derivation
  `/nix/store/vxx22hmmjmxrf0jyrnh8qhpw0gqbp1k1-discord-1.0.154.drv`, and
  `providerErrors=[]`.
- Windows manifest: exactly one `Discord.Discord` Winget entry with
  `installFeature = "WithHermes"`.

## Controller live acceptance (PASS)

- Activation succeeded on active system
  `/nix/store/c5cj275qhrj6867kyl7dm38m7ppnpycr-darwin-system-26.11.4cff07d`.
  Home Manager completed and emitted `[Nix] Disabling updates already done`.
  The direnv warning was only the unapproved worktree `.envrc`, not an
  activation failure.
- `launchctl print gui/501/org.nixos.discord-module-staging` confirmed
  `/Users/ktome1995/Library/LaunchAgents/org.nixos.discord-module-staging.plist`,
  `RunAtLoad`, false PathState for the exact `installed.json`, the expected
  stage/store module arguments, `state = not running`, and last exit status 0.
  `installed.json` existed immediately after activation.
- First exact `/Applications/Nix Apps/Discord.app` launch stayed alive after
  15 seconds as PID 65985 (`com.hnc.Discord`). Its `installed.json` mtime
  advanced from 1788125558 to 1788125607; LaunchAgent runs advanced 2 to 3
  with exit 0. Orca Cmd-Q completed a normal exit while preserving the file.
- Second exact launch stayed alive after 15 seconds as PID 68712
  (`com.hnc.Discord`). The mtime advanced from 1788125607 to 1788125673 and
  LaunchAgent runs reached 5 with exit 0.
- After the second normal exit, the launch-enabled formal verifier completed
  with exit 0. Its exact-store app process PID 71741 was alive after 12
  seconds; `installed.json` mtime became 1788125736 and LaunchAgent runs
  reached 7 with exit 0.
- The default profile evaluated exactly to
  `{casks:false, system:false, home:false}`. `/Applications/Nix Apps/Discord.app`
  exists; `/Applications/Discord.app` and a Home Manager app copy do not. The
  Homebrew `discord` cask is absent. `~/Library/Application Support/discord`
  and `~/Library/Preferences/com.hnc.Discord.plist` remain preserved.

## Remaining issue

None. Future Discord package-version updates continue to monitor the
version-derived `installed.json` path. The legacy cask migration is complete
and did not use `--zap`.

## Review fix round 1/5: artifact bundle identity

- Added direct artifact assertions in
  `Darwin Discord keeps staged modules outside its signed application bundle`.
  After realizing `.#darwin-discord`, the test reads
  `Applications/Discord.app/Contents/Info.plist` with macOS `plutil` and
  requires `CFBundleIdentifier = com.hnc.Discord` and
  `CFBundleExecutable = Discord`; this is independent of the support-report
  metadata and signature/Gatekeeper checks.
- RED: with a temporary expected identifier of `com.example.WrongDiscord`,
  `bats --filter 'Darwin Discord keeps staged modules outside its signed
application bundle' tests/bash/package_catalog.bats` produced 0 passed and
  1 failed at the new identifier assertion.
- GREEN: restoring the literal `com.hnc.Discord` made the same focused command
  pass 1/1. `bats tests/bash/package_catalog.bats tests/bash/macos_config.bats`
  then passed 63/63 and `PackageCatalog.Tests.ps1` passed 49/49.
