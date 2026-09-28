# Opt-in session tools; excluded from headless Home Manager consumers.
{ pkgs, lib, ... }:
lib.genAttrs [ "hyprland" "fuzzel" "firefox" "nautilus" ] (name: {
  pkg = if pkgs.stdenv.hostPlatform.isLinux then pkgs.${name} else null;
  category = "native-desktop";
  installFeature = "WithDesktop";
  support = {
    linux = {
      provider = "nix";
      source = "nixpkgs";
      nixAttr = name;
      identity = name;
    };
    darwin.unsupported = "This package belongs to the native NixOS desktop session; macOS uses AeroSpace and native applications";
    windows.unsupported = "This package belongs to the native NixOS desktop session, not the Windows host or WSL guest";
  };
})
