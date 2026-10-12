{ pkgs }:
let
  terminals = ../../modules/terminals;
  windowsWezTerm = ../../../chezmoi/terminals/wezterm/wezterm.lua;
  settings =
    (import (terminals + "/wezterm/defaults.nix") {
      inherit pkgs;
      inherit (pkgs) lib;
    }).programs.wezterm.settings;
in
pkgs.runCommand "wezterm-config-check"
  {
    nativeBuildInputs = [
      pkgs.bats
      pkgs.chezmoi
      pkgs.lua
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    luac -p ${terminals}/wezterm/wezterm.lua
    luac -p ${windowsWezTerm}
    lua - ${windowsWezTerm} \
      ${pkgs.lib.escapeShellArg "UDEV Gothic NF"} \
      ${toString settings.font_size} \
      ${pkgs.lib.escapeShellArg settings.color_scheme} <<'LUA'
    package.loaded.wezterm = nil
    package.preload.wezterm = function()
      return {
        target_triple = "x86_64-pc-windows-msvc",
        default_wsl_domains = function()
          return { { name = "WSL:NixOS", distribution = "NixOS" } }
        end,
        config_builder = function() return {} end,
        font = function(family) return family end,
        action_callback = function(callback) return callback end,
        action = setmetatable({}, { __index = function() return function() return {} end end }),
      }
    end
    local config = dofile(arg[1])
    assert(config.font == arg[2], "font family differs")
    assert(config.font_size == tonumber(arg[3]), "font size differs")
    assert(config.color_scheme == arg[4], "theme differs")
    assert(config.default_prog[1] == "pwsh.exe", "PowerShell must be the default shell")
    assert(config.default_prog[2] == "-NoLogo", "PowerShell must start without its logo")
    local has_nixos_wsl = false
    for _, domain in ipairs(config.wsl_domains) do
      if domain.name == "WSL:NixOS" and domain.distribution == "NixOS" then
        has_nixos_wsl = true
      end
    end
    assert(has_nixos_wsl, "default WSL domains must include NixOS")
    local has_nixos_launcher = false
    for _, entry in ipairs(config.launch_menu) do
      if entry.label == "NixOS (WSL)"
        and type(entry.domain) == "table"
        and entry.domain.DomainName == "WSL:NixOS"
      then
        has_nixos_launcher = true
      end
    end
    assert(has_nixos_launcher, "launch menu must expose NixOS WSL")
    print("Windows WezTerm default shell and NixOS WSL launcher are valid")
    LUA
    WEZTERM_TEST_REPO_ROOT=${../../..} bats ${../../../tests/bash/wezterm_config.bats}
    touch "$out"
  ''
