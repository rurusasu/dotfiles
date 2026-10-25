{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    sharedConfig
    lib
    ;
  sessionDefaults = variables: {
    defaultCommand = variables.FZF_DEFAULT_COMMAND or null;
    filePreview = variables.FZF_FILE_PREVIEW or null;
    dirPreview = variables.FZF_DIR_PREVIEW or null;
    fileWidgetCommand = variables.FZF_CTRL_T_COMMAND or null;
    fileWidgetOptions = variables.FZF_CTRL_T_OPTS or null;
    changeDirWidgetCommand = variables.FZF_ALT_C_COMMAND or null;
    changeDirWidgetOptions = variables.FZF_ALT_C_OPTS or null;
    defaultOptions = variables.FZF_DEFAULT_OPTS or null;
  };
in
{
  testFzfSharedDefaultsAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
        fzfPackage = builtins.unsafeDiscardStringContext (toString programs.fzf.package);
      in
      sessionDefaults home.config.home.sessionVariables
      // {
        enabled = programs.fzf.enable;
        bashIntegration = programs.fzf.enableBashIntegration;
        zshIntegration = programs.fzf.enableZshIntegration;
        fzfInit =
          lib.hasInfix "source ${fzfPackage}/share/fzf/key-bindings.zsh" programs.zsh.initContent
          && lib.hasInfix "source ${fzfPackage}/share/fzf/completion.zsh" programs.zsh.initContent;
      }
    ) homes;
    expected = map (
      _:
      sessionDefaults sharedConfig.home.sessionVariables
      // {
        enabled = sharedConfig.programs.fzf.enable;
        bashIntegration = sharedConfig.programs.fzf.enableBashIntegration;
        zshIntegration = sharedConfig.programs.fzf.enableZshIntegration;
        fzfInit = true;
      }
    ) homes;
  };
}
