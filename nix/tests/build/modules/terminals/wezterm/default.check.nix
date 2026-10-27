{
  pkgs,
  fixtures,
  files,
}:
{
  wezterm-config =
    let
      unixWezTerm = files.nix.modules.terminals.wezterm."wezterm.lua";
      windowsWezTerm = files.chezmoi.terminals.wezterm."wezterm.lua";
      settings = terminalHome.config.programs.wezterm.settings;
      terminalHome = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
        {
          home = {
            username = "test-user";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            stateVersion = "25.05";
          };
          programs = {
            wezterm.enable = true;
            bash.enable = true;
            zsh.enable = true;
          };
        }
      ];
      terminfoDirectory = "${terminalHome.config.programs.wezterm.package.terminfo}/share/terminfo";
    in
    pkgs.runCommand "wezterm-config-check"
      {
        nativeBuildInputs = [
          pkgs.lua
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        luac -p ${unixWezTerm}
        luac -p ${windowsWezTerm}
        lua - ${windowsWezTerm} \
          ${pkgs.lib.escapeShellArg "UDEV Gothic NF"} \
          ${toString settings.font_size} \
          ${pkgs.lib.escapeShellArg settings.color_scheme} \
          ${pkgs.writeText "wezterm-darwin-config.lua" ''
            local dotfiles_terminfo_directory = ${pkgs.lib.generators.toLua { } terminfoDirectory}
            ${builtins.readFile unixWezTerm}
          ''} \
          ${pkgs.lib.escapeShellArg terminfoDirectory} <<'LUA'
        local target_triple = "x86_64-pc-windows-msvc"
        package.loaded.wezterm = nil
        package.preload.wezterm = function()
          return {
            target_triple = target_triple,
            default_wsl_domains = function()
              return { { name = "WSL:NixOS", distribution = "NixOS" } }
            end,
            config_builder = function() return {} end,
            font = function(family) return family end,
            action_callback = function(callback) return callback end,
            action = setmetatable({}, {
              __index = function(_, name)
                return function(value) return { [name] = value } end
              end,
            }),
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

        target_triple = "aarch64-apple-darwin"
        package.loaded.wezterm = nil
        local getenv = os.getenv
        os.getenv = function(name)
          if name == "TERMINFO_DIRS" then return "/inherited/terminfo" end
          return getenv(name)
        end
        config = dofile(arg[5])
        os.getenv = getenv
        assert(config.set_environment_variables.TERMINFO_DIRS
          == arg[6] .. ":/usr/share/terminfo:/inherited/terminfo",
          "Darwin child shells must receive package, system and inherited terminfo paths")
        assert(config.use_ime == true, "Darwin IME support must remain enabled")
        local backspace, leader_backspace
        for _, binding in ipairs(config.keys) do
          if binding.key == "Backspace" and binding.mods == "NONE" then backspace = binding.action end
          if binding.key == "Backspace" and binding.mods == "LEADER" then leader_backspace = binding.action end
        end
        assert(backspace and backspace.SendString == string.char(127), "Darwin Backspace must send DEL")
        assert(leader_backspace and leader_backspace.SendKey
          and leader_backspace.SendKey.key == "Backspace" and leader_backspace.SendKey.mods == nil,
          "Backspace after the leader must send an unmodified Backspace key")
        print("Darwin WezTerm terminfo inheritance, IME and Backspace bindings are valid")
        LUA
        # Execute the generated shell startup with the real WezTerm integration.
        # WezTerm hooks must load in WezTerm and stay absent in Ghostty.
        for terminal in ghostty WezTerm; do
          for shell in bash zsh; do
            case "$shell" in
              bash) executable=${pkgs.bash}/bin/bash; init=${pkgs.writeText "wezterm-bash-init" terminalHome.config.programs.bash.initExtra}; args="--noprofile --norc" ;;
              zsh) executable=${pkgs.zsh}/bin/zsh; init=${pkgs.writeText "wezterm-zsh-init" terminalHome.config.programs.zsh.initContent}; args="-d -f" ;;
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
      '';
}
