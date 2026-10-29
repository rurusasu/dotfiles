{
  pkgs,
  fixtures,
  files,
}:
{
  wezterm-config =
    let
      unixWezTerm = files.nix.modules.terminals.wezterm."wezterm.lua";
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
        lua - ${pkgs.writeText "wezterm-darwin-config.lua" ''
          local dotfiles_terminfo_directory = ${pkgs.lib.generators.toLua { } terminfoDirectory}
          ${builtins.readFile unixWezTerm}
        ''} \
          ${pkgs.lib.escapeShellArg terminfoDirectory} <<'LUA'
        package.preload.wezterm = function()
          return {
            target_triple = "aarch64-apple-darwin",
            config_builder = function() return {} end,
            action_callback = function(callback) return callback end,
            action = setmetatable({}, {
              __index = function(_, name)
                return function(value) return { [name] = value } end
              end,
            }),
          }
        end
        local getenv = os.getenv
        os.getenv = function(name)
          if name == "TERMINFO_DIRS" then return "/inherited/terminfo" end
          return getenv(name)
        end
        local config = dofile(arg[1])
        os.getenv = getenv
        assert(config.set_environment_variables.TERMINFO_DIRS
          == arg[2] .. ":/usr/share/terminfo:/inherited/terminfo",
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
