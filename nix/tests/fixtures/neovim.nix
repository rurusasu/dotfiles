{ fixtures, pkgs }:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    (fixtures.homeModule "common")
    ({ lib, ... }: {
      home.homeDirectory = lib.mkForce "/tmp/neovim-test-home";
      home.stateVersion = lib.mkForce "26.05";
      programs.nixvim.enable = true;
    })
  ];
in
{
  package = home.config.programs.nixvim.build.package;
  servers = builtins.attrNames (
    home.pkgs.lib.filterAttrs (
      name: server: name != "*" && server.enable
    ) home.config.programs.nixvim.lsp.servers
  );
}
