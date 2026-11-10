{
  programs.nixvim =
    {
      config,
      lib,
      hmConfig,
      ...
    }:
    {
      config = lib.mkIf config.enable {
        colorschemes.catppuccin = {
          enable = true;
          settings = {
            flavour = hmConfig.catppuccin.flavor;
            transparent_background = true;
          };
        };
      };
    };
}
