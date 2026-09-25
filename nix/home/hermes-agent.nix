{
  config,
  inputs,
  installFeatures ? [ ],
  ...
}:
let
  enabled = builtins.elem "WithHermes" installFeatures;
in
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  programs.hermes-agent.enable = enabled;
  home.sessionVariables.DOTFILES_WITH_HERMES = if enabled then "1" else "0";
  services.hermes-agent = {
    enable = enabled;
    gateway.enable = enabled;
    hermesHome = "${config.home.homeDirectory}/.hermes";
    settings.gateway.multiplex_profiles = true;
  };
}
