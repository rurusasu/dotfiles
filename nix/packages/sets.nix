# Compatibility entrypoint for the cross-platform package catalog.
# Package identities live in catalog/, provider logic in providers/, and
# installation metadata in install/. Public arguments and outputs stay here.
#
# Exported attributes:
#   - catalog categories (core, dev, terminal, editors, llm, …) → lists of derivations
#   - all                → flat list of all derivations
#   - wingetMap          → nix attr name → winget PackageIdentifier
#   - msstoreMap         → nix attr name → Microsoft Store Product ID
#   - npmMap             → nix attr name → npm package spec
#   - pnpmGlobal         → cross-platform pnpm global package names
#   - npmVerify          → catalog attr name → { command, args } for npm verification
#   - pnpmVerify         → package name → { command, args } for post-install verification
#   - pnpmPostInstall    → package name → { command, args } to run after pnpm add -g
#   - pnpmInstallArgs    → package name → extra pnpm add -g arguments
#   - wingetVerify       → catalog attr name → { command, args } for post-install verification
#   - msstoreVerifyById  → Microsoft Store Product ID → { command, args } for post-install verification
#   - wingetInstallArgs  → catalog attr name → extra winget install arguments
#   - wingetRequiresAdmin → catalog attr name or winget ID → administrator-only install
#   - packageInstallTimeoutSeconds → shared install timeout for package adapters
#   - wingetInstallTimeoutSeconds → optional catalog attr name or winget ID overrides
#   - wingetDirectInstallers → catalog attr name or winget ID → direct installer metadata
#   - wingetSkipInstall → catalog attr name or winget/msstore ID → skip normal automated install
#   - wingetCiSkipInstall → catalog attr name or winget/msstore ID → skip CI winget install smoke test
#   - wingetPathEntries  → catalog attr name or winget ID → extra Windows PATH directories
#   - supportReport      → per-package Windows/Darwin/Linux provider metadata
#   - darwinCasks        → Homebrew casks derived from provider metadata
#   - darwinBrews        → Homebrew formulas derived from provider metadata
#   - providerErrors     → unresolved provider metadata (must remain empty)
#   - windowsOnly        → packages with no nix equivalent (winget/msstore/npm/pnpm)
#
# Imported by:
#   - nix/packages/outputs.nix → export and validation artifacts
#   - nix/hosts/aarch64-darwin/home.nix     → home.packages on macOS
#   - nix/hosts/shared/linux-home.nix      → home.packages with native desktop packages excluded
#   - nix/hosts/x86_64-linux/wsl/home.nix        → home.packages with native desktop packages excluded
#   - nix/packages/winget.nix → winget/npm/pnpm JSON generation
{
  pkgs,
  lib,
  # Accepted for existing callers; Codex CLI is supplied by the ChatGPT app.
  codexPackage ? null,
  catalogOverride ? null,
}:
let
  context = import ./catalog/context.nix { inherit pkgs; };
  common = import ./providers/common.nix { inherit pkgs lib; };
  windowsOnly = import ./install/windows-only.nix { inherit (common) providerSource; };
  rawCatalog =
    if catalogOverride != null then catalogOverride else import ./catalog { inherit pkgs lib context; };
  normalized = import ./providers/normalize.nix {
    inherit lib rawCatalog;
    inherit (common) supports;
    inherit (windowsOnly) windowsOnlySupport;
  };
  selection = import ./providers/selection.nix {
    inherit pkgs lib;
    inherit (normalized) catalog;
    inherit (common) supports platformKey;
  };
  installation = import ./install {
    inherit pkgs lib windowsOnly;
    inherit (normalized) catalog;
  };
in
selection
// installation
// {
  inherit (context) appearance selectDarwinPackage;
  inherit (normalized) supportReport;
  # Keep sets.all backward compatible while allowing headless consumers to
  # exclude session-only packages without duplicating the catalog IDs.
  nativeDesktopPackageNames = builtins.attrNames (
    lib.filterAttrs (_: entry: entry.category == "native-desktop") normalized.catalog
  );
  providerErrors = import ./providers/validation.nix {
    inherit pkgs lib;
    inherit (normalized) catalog supportReport;
    inherit (common) supports platformKey;
  };
}
