{
  inputs,
  pkgs,
  configDirectory ? ".config",
}:
let
  testPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = testPkgs;
    modules = [
      ../../modules/nvim
      {
        home = {
          username = "test-user";
          homeDirectory = "/tmp/neovim-test-home";
          stateVersion = "26.05";
        };
        xdg.configHome = "/tmp/neovim-test-home/${configDirectory}";
      }
    ];
  };
  # Exercise the evaluated file-activation DAG, including HM's real collision
  # checker/linker, without installing a profile or touching a host home.
  fileActivation = inputs.home-manager.lib.hm.dag.topoSort (
    pkgs.lib.getAttrs [
      "checkNeovimLegacyConfig"
      "checkLinkTargets"
      "writeBoundary"
      "migrateNeovimLegacyConfig"
      "linkGeneration"
    ] home.config.home.activation
  );
in
{
  package = home.config.programs.neovim.finalPackage;
  plugins = home.config.xdg.dataFile."nvim/site/pack/hm".source;
  lua = home.config.xdg.configFile."nvim/lua".source;
  init = pkgs.writeText "neovim-init.lua" home.config.programs.neovim.initLua;
  homeFiles = home.config.home-files;
  fileActivation = pkgs.writeShellScript "neovim-file-activation-test" ''
    set -euo pipefail
    ${home.config.lib.bash.initHomeManagerLib}
    export HOME_MANAGER_BACKUP_COMMAND=""
    export HOME_MANAGER_BACKUP_EXT=""
    export HOME_MANAGER_BACKUP_OVERWRITE=""
    export VERBOSE_ARG=""
    newGenPath="$1"
    phase="$2"
    if [[ $phase == dry-run-local ]]; then
      DRY_RUN=""
      export -n DRY_RUN
    fi
    # Driver v1 owns profile updates; these tests exercise file activation only.
    hmDriverVersion=1
    ${pkgs.lib.concatMapStringsSep "\n" (entry: ''
      ${pkgs.lib.optionalString (entry.name == "writeBoundary") ''
        if [[ $phase == check ]]; then
          exit 0
        fi
      ''}
      ${pkgs.lib.optionalString (entry.name == "linkGeneration") ''
        if [[ $phase == dry-run-local ]]; then
          exit 0
        fi
      ''}
      ${entry.data}
    '') fileActivation.result}
  '';
}
