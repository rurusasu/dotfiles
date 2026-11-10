{
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      plugins.lspconfig.enable = true;
    };
  };
}
