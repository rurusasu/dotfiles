{ inputs, pkgs }:
let
  terminals = ../../modules/terminals;
  windowsWezTerm = ../../../chezmoi/terminals/wezterm/wezterm.lua;
  settings =
    (import (terminals + "/wezterm/defaults.nix") {
      inherit pkgs;
      inherit (pkgs) lib;
      inherit (terminalHome) config;
    }).programs.wezterm.settings;
  terminalHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      (terminals + "/wezterm/defaults.nix")
      {
        home = {
          username = "test-user";
          homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
          stateVersion = "25.05";
        };
        programs.bash.enable = true;
        programs.zsh.enable = true;
      }
    ];
  };
  bashInit = pkgs.writeText "wezterm-bash-init" terminalHome.config.programs.bash.initExtra;
  zshInit = pkgs.writeText "wezterm-zsh-init" terminalHome.config.programs.zsh.initContent;
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

    # Execute the generated shell startup with the real WezTerm integration.
    # Ghostty must retain its own prompt hooks; WezTerm must retain its hooks.
    for terminal in ghostty WezTerm; do
      for shell in bash zsh; do
        case "$shell" in
          bash) executable=${pkgs.bash}/bin/bash; init=${bashInit}; args="--noprofile --norc" ;;
          zsh) executable=${pkgs.zsh}/bin/zsh; init=${zshInit}; args="-d -f" ;;
        esac
        TERM=xterm-256color TERM_PROGRAM="$terminal" "$executable" $args -ic '
          source "$1"
          if typeset -f __wezterm_osc7 >/dev/null; then loaded=yes; else loaded=no; fi
          if [ "$TERM_PROGRAM" = WezTerm ]; then expected=yes; else expected=no; fi
          if [ "$loaded" != "$expected" ]; then
            echo "$TERM_PROGRAM: unexpected WezTerm shell hooks (loaded=$loaded)" >&2
            exit 1
          fi
        ' terminal-test "$init"
        echo "$terminal/$shell: terminal-specific shell integration passed"
      done
    done
    touch "$out"
  ''
