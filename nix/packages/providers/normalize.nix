# Complete implicit providers while preserving explicit platform declarations.
{
  lib,
  rawCatalog,
  supports,
  windowsOnlySupport,
}:
let
  # Provider gaps are reviewed explicitly. Adding a package without a provider
  # now fails providerErrors until its unsupported platform is listed here.
  reviewedUnsupported = {
    windows = lib.genAttrs [
      "argocd"
      "astro-language-server"
      "bat"
      "bats"
      "cilium-cli"
      "cmake"
      "dive"
      "ghostscript"
      "gnumake"
      "gopls"
      "gwq"
      "k9s"
      "kind"
      "kubectl"
      "kubectx"
      "kubernetes-helm"
      "kubeseal"
      "kustomize"
      "netcat"
      "neovim-remote"
      "nixd"
      "p7zip"
      "pnpm"
      "pre-commit"
      "python3"
      "rustfmt"
      "sops"
      "stern"
      "tmux"
      "treefmt"
      "trivy"
      "unzip"
      "workmux"
    ] (_: "No reviewed Windows package provider is selected");
    darwin = { };
    linux = { };
  };

  reviewedUnsupportedFor = platform: name: lib.attrByPath [ platform name ] null reviewedUnsupported;

  defaultSupport =
    name: entry:
    let
      package = entry.pkg or null;
      unsupported = platform: reviewedUnsupportedFor platform name;
    in
    {
      windows =
        if (entry.winget or null) != null then
          {
            provider = "winget";
            source = "winget";
            identity = entry.winget;
          }
        else if (entry.msstore or null) != null then
          {
            provider = "msstore";
            source = "msstore";
            identity = entry.msstore;
          }
        else if (entry.npm or null) != null then
          {
            provider = "npm";
            source = "npm";
            identity = entry.npm;
          }
        else
          let
            reason = unsupported "windows";
          in
          if reason == null then { } else { unsupported = reason; };
      darwin =
        if supports package "aarch64-darwin" || supports package "x86_64-darwin" then
          {
            provider = "nix";
            source = "nixpkgs";
            identity = name;
            nixAttr = name;
          }
        else
          let
            reason = unsupported "darwin";
          in
          if reason == null then { } else { unsupported = reason; };
      linux =
        if supports package "x86_64-linux" || supports package "aarch64-linux" then
          {
            provider = "nix";
            source = "nixpkgs";
            identity = name;
            nixAttr = name;
          }
        else
          let
            reason = unsupported "linux";
          in
          if reason == null then { } else { unsupported = reason; };
    };

  catalog = lib.mapAttrs (
    name: entry:
    entry
    // {
      support = defaultSupport name entry // (entry.support or { });
    }
  ) rawCatalog;

  supportReport =
    lib.mapAttrs (
      _: entry:
      entry.support
      // {
        installFeature = entry.installFeature or null;
        legacyDarwin = entry.legacyDarwin or null;
      }
    ) catalog
    // lib.mapAttrs (
      _: support:
      support
      // {
        installFeature = null;
        legacyDarwin = null;
      }
    ) windowsOnlySupport;
in
{
  inherit catalog supportReport;
}
