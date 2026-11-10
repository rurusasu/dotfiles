{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.nvim-surround.enable = true;
      };
    };
}
