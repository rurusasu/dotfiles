{ pkgs }:
let
  terminals = ../../modules/terminals;
  settings =
    (import (terminals + "/wezterm/defaults.nix") {
      inherit pkgs;
      lib = pkgs.lib;
    }).programs.wezterm.settings;

in
pkgs.runCommand "ghostty-config-check"
  {
    nativeBuildInputs = [
      pkgs.bats
      pkgs.chezmoi
      pkgs.lua
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export GHOSTTY_TEST_REPO_ROOT=${../../..}
    mkdir -p "$HOME"
    luac -p ${terminals}/wezterm/wezterm.lua
    luac -p ${../../../chezmoi/terminals/wezterm/wezterm.lua}
    lua - ${../../../chezmoi/terminals/wezterm/wezterm.lua} \
      ${pkgs.lib.escapeShellArg "UDEV Gothic NF"} \
      ${toString settings.font_size} \
      ${pkgs.lib.escapeShellArg settings.color_scheme} <<'LUA'
    for _, platform in ipairs({ "x86_64-unknown-linux-gnu", "aarch64-apple-darwin", "x86_64-pc-windows-msvc" }) do
      package.loaded.wezterm = nil
      package.preload.wezterm = function()
        return {
          target_triple = platform,
          config_builder = function() return {} end,
          font = function(family) return family end,
          action_callback = function(callback) return callback end,
          action = setmetatable({}, { __index = function() return function() return {} end end }),
        }
      end
      local config = dofile(arg[1])
      assert(config.font == arg[2], "font family differs on " .. platform)
      assert(config.font_size == tonumber(arg[3]), "font size differs on " .. platform)
      assert(config.color_scheme == arg[4], "theme differs on " .. platform)
      print("WezTerm module settings: " .. platform)
    end
    LUA
    bats ${../../../tests/bash/ghostty_config.bats}
    touch "$out"
  ''
