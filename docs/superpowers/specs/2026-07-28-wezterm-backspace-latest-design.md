# WezTerm Backspace and macOS Nightly Design

## Context

WezTerm uses `Ctrl+Space` as a two-second leader key. While the leader is
active, an unassigned Backspace event is consumed instead of being sent to the
foreground terminal application.

On macOS, WezTerm is currently installed from the pinned nixpkgs package.
LaunchServices can retain an older Nix Store application path after the command
in the active Home Manager profile has moved to a newer store path. The package
catalog already defines Homebrew casks as the provider for macOS GUI
applications and upgrades them during every nix-darwin activation.

## Goals

- Send Backspace to the foreground application even when the WezTerm leader is
  active.
- Install WezTerm nightly from a stable `/Applications/WezTerm.app` path on
  macOS.
- Upgrade the macOS GUI and bundled CLI commands together during every
  nix-darwin activation.
- Preserve the existing Nix provider on Linux and nightly winget provider on
  Windows.

## Design

Add a `LEADER+Backspace` key assignment that performs
`SendKey({ key = "Backspace" })`. This consumes the leader state while
forwarding the Backspace event to the active pane.

Change the WezTerm catalog entry so its Nix package is omitted only while
evaluating on Darwin. Declare `wezterm@nightly` as the Darwin Homebrew cask and
declare the Nix provider explicitly for Linux. The existing nix-darwin
configuration already enables `autoUpdate`, `upgrade`, and `greedyCasks`, so no
second update mechanism is needed.

The Homebrew nightly cask is intentionally selected instead of the stable cask:
its version is `latest`, it downloads WezTerm's upstream nightly release, and it
installs both `WezTerm.app` and the bundled CLI commands.

## Verification

- A Pester keybinding contract requires the leader Backspace passthrough.
- A Bats package-catalog contract requires the Darwin nightly cask, explicit
  Linux Nix provider, and Darwin exclusion of the Nix package.
- Each new contract is run before implementation to observe the expected
  failure and again after implementation to observe success.
- Run formatting, focused tests, package-provider evaluation, and the relevant
  repository test suites.

## Non-Goals

- Changing the leader key or timeout.
- Changing the Linux or Windows WezTerm release channel.
- Adding an updater outside the existing nix-darwin/Homebrew activation path.
