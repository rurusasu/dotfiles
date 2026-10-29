{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.starship;
  windowsHelperEnabled = cfg.wslIntegration.enable && pkgs.stdenv.hostPlatform.isLinux;
  windowsHelper = pkgs.writeShellScript "starship-windows" ''
    exec "''${DOTFILES_WINDOWS_STARSHIP:-starship.exe}" "$@"
  '';
  windowsHelperInitialization = ''
    # Resolve the Windows executable once instead of searching PATH at every prompt.
    export DOTFILES_WINDOWS_STARSHIP="$(command -v starship.exe)"
  '';
  osSymbol =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "🍎 "
    else if pkgs.stdenv.hostPlatform.isLinux then
      "❄️ "
    else
      null;
  osStyle = "bold white";
in
{
  options.programs.starship = {
    wslIntegration.enable = lib.mkEnableOption (
      "Windows Starship Git status with cached executable lookup in WSL"
    );
    asyncZsh = {
      enable = lib.mkEnableOption "asynchronous Starship left-prompt rendering in Zsh";
      package = lib.mkPackageOption pkgs "pure-prompt" { };
    };
  };

  config = lib.mkIf cfg.enable {
    # Replace the previously deployed TOML when Home Manager takes ownership.
    home.file = {
      ${cfg.configPath}.force = true;
    };

    programs.bash.initExtra = lib.mkIf (
      windowsHelperEnabled && config.programs.bash.enable && cfg.enableBashIntegration
    ) windowsHelperInitialization;
    assertions = [
      {
        assertion = !cfg.asyncZsh.enable || (config.programs.zsh.enable && cfg.enableZshIntegration);
        message = "programs.starship.asyncZsh.enable requires Zsh and Starship's Zsh integration.";
      }
    ];

    programs.zsh.initContent = lib.mkMerge [
      (lib.mkIf (
        windowsHelperEnabled && config.programs.zsh.enable && cfg.enableZshIntegration
      ) windowsHelperInitialization)
      (lib.mkIf cfg.asyncZsh.enable (
        # Starship initializes at 1000; Patina's highlight hook remains last.
        lib.mkOrder 1400 ''
          source ${./async.zsh} ${lib.getExe cfg.package} \
            ${cfg.asyncZsh.package}/share/zsh/site-functions/async ${pkgs.coreutils}/bin/timeout
        ''
      ))
    ];

    programs.starship = {
      enableZshIntegration = true;
      enableBashIntegration = true;
      asyncZsh.package = lib.mkDefault (
        pkgs.pure-prompt.overrideAttrs (previous: {
          # command -p uses /bin:/usr/bin, bypassing Nix dependencies in PATH.
          postPatch = (previous.postPatch or "") + ''
            substituteInPlace async.zsh \
              --replace-fail 'command -p cat' '${lib.getExe' pkgs.coreutils "cat"}'
          '';
        })
      );

      settings = {
        add_newline = true;
        scan_timeout = 500;
        format =
          (if osSymbol == null then "$os" else "[${osSymbol}](${osStyle}) ")
          + "$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";

        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[x](bold red)";
        };

        os = {
          disabled = osSymbol != null;
          format = "[$symbol]($style) ";
          style = osStyle;
        };

        username = {
          show_always = true;
          format = "[$user]($style)";
        };

        hostname = {
          ssh_only = false;
          format = "@[$hostname]($style) ";
        };

        memory_usage = {
          disabled = false;
          threshold = 0;
          format = "[$ram]($style) ";
        };

        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
        };

        git_branch = {
          symbol = " ";
          format = "on [$symbol$branch]($style) ";
        };

        git_status = {
          ahead = "";
          behind = "";
          diverged = "";
        }
        // lib.optionalAttrs windowsHelperEnabled { windows_starship = toString windowsHelper; };

        nix_shell = {
          symbol = " ";
          format = "[$symbol$state]($style) ";
        };
      };
    };
  };
}
