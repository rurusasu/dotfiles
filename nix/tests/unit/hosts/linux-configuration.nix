{ inputs }:
let
  host = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [ ../../../hosts/linux ];
  };
  inherit (host) config pkgs;
in
{
  testLinuxInstallsZshBeforeSelectingItAsLoginShell = {
    expr = {
      enabled = config.programs.zsh.enable;
      selected = config.users.users.nixos.shell == pkgs.zsh;
      installed = builtins.elem pkgs.zsh config.environment.systemPackages;
    };
    expected = {
      enabled = true;
      selected = true;
      installed = true;
    };
  };
}
