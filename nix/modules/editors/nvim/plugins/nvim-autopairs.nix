{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.nvim-autopairs = {
          enable = true;
          settings.map_cr = false;
        };
      };
    };
}
