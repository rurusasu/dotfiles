{ config, lib, ... }: {
  config = lib.mkIf config.programs.lazygit.enable {
    programs.lazygit = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}
