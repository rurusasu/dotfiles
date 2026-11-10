{
  pkgs,
  fixtures,
  files,
}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  starship-async =
    let
      home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
        { programs.starship.enable = true; }
      ];
    in
    pkgs.runCommand "starship-async-check" { } ''
      ${pkgs.python3}/bin/python3 ${files.nix.tests.fixtures.starship."async.py"} \
        --adapter ${files.nix.modules.shells.plugins.starship."async.zsh"} \
        --zsh ${pkgs.zsh}/bin/zsh \
        --starship ${pkgs.lib.getExe home.config.programs.starship.package} \
        --async-library ${home.config.programs.starship.asyncZsh.package}/share/zsh/site-functions/async \
        --timeout ${pkgs.coreutils}/bin/timeout \
        --path ${pkgs.lib.makeBinPath [ pkgs.coreutils ]} \
        --output "$out"
    '';

  starship-windows-helper =
    let
      home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
        {
          programs = {
            bash.enable = true;
            zsh = {
              enable = true;
              history.path = pkgs.lib.mkForce "/dev/null";
            };
            starship = {
              enable = true;
              wslIntegration.enable = true;
            };
          };
        }
      ];
      bashInit = home.config.home.file.".bashrc".source;
      zshInit =
        home.config.home.file."${
          pkgs.lib.removePrefix (home.config.home.homeDirectory + "/") home.config.programs.zsh.dotDir
        }/.zshrc".source;
    in
    pkgs.runCommand "starship-windows-helper-check"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.zsh
        ];
      }
      ''
        bash ${files.nix.tests.fixtures.starship."windows-helper.sh"} \
          ${home.config.programs.starship.settings.git_status.windows_starship} \
          ${pkgs.bash}/bin/bash ${bashInit} \
          ${pkgs.zsh}/bin/zsh ${zshInit}
        touch "$out"
      '';
}
