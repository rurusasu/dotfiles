{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.rust_analyzer.enable)
      [
        pkgs.rustup
        (lib.hiPrio pkgs.rust-analyzer)
        (lib.hiPrio pkgs.rustfmt)
      ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.rust_analyzer = {
        enable = true;
        package = null;
      };
    };
  };
}
