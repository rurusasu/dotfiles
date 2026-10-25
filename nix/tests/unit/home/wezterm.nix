{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  fixtures = homeConfigurations;
  inherit (fixtures) homes lib;
in
{
  testWeztermShellIntegrationsAreGeneratedAcrossHomes = {
    expr = map (home: {
      bashWezterm = lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.bash.initExtra;
      zshWezterm = lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.zsh.initContent;
    }) homes;
    expected = map (_: {
      bashWezterm = true;
      zshWezterm = true;
    }) homes;
  };
}
