{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
  configuredIntegration =
    (import ../../../../../modules/shells/plugins/ripgrep.nix {
      lib = lib // {
        mkBefore = value: value;
      };
    }).programs.zsh.initContent;
in
{
  testRipgrepSettingsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.ripgrep.enable;
      packageName = home.config.programs.ripgrep.package.pname;
      configPath = home.config.home.sessionVariables.RIPGREP_CONFIG_PATH;
      config = home.config.home.file."${home.config.xdg.configHome}/ripgrep/ripgreprc".text;
    }) homes;
    expected = map (home: {
      enabled = true;
      packageName = "ripgrep";
      configPath = "${home.config.xdg.configHome}/ripgrep/ripgreprc";
      config = lib.concatLines home.config.programs.ripgrep.arguments;
    }) homes;
  };

  testRipgrepFzfIntegrationIsGeneratedAcrossHomes = {
    # The canonical block covers its guard, function, both reload bindings,
    # bat preview, and editor invocation without copying those shell commands.
    expr = map (
      home:
      let
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text;
      in
      {
        configuredIntegration =
          lib.trim configuredIntegration != "" && lib.hasInfix (lib.trim configuredIntegration) zshrc;
        guarded = lib.hasInfix "if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then" zshrc;
        functionDefined = lib.hasInfix "rfg() {" zshrc;
      }
    ) homes;
    expected = map (_: {
      configuredIntegration = true;
      guarded = true;
      functionDefined = true;
    }) homes;
  };
}
