{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.web-devicons.enable = true;
      };
    };
}
