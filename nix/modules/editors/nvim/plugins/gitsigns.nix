{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.gitsigns.enable = true;
      };
    };
}
