{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
  configuredPreview =
    (import ../../../home/shells/plugins/fzf.nix {
      lib = lib // {
        mkBefore = value: value;
      };
    }).programs.zsh.initContent;
in
{
  testFzfConfigurationAndShellIntegrationAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
        fzfPackage = builtins.unsafeDiscardStringContext (toString programs.fzf.package);
        variables = home.config.home.sessionVariables;
        fzfVariables = lib.filterAttrs (name: _: lib.hasPrefix "FZF_" name) variables;
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" programs.zsh.dotDir}/.zshrc".text;
      in
      {
        enabled = programs.fzf.enable;
        bashIntegration = programs.fzf.enableBashIntegration;
        zshIntegration = programs.fzf.enableZshIntegration;
        defaultOptionsConfigured = variables ? FZF_DEFAULT_OPTS;
        configuredVariablesExported =
          fzfVariables != { }
          && builtins.all (
            name:
            lib.hasInfix (home.config.lib.shell.export name
              fzfVariables.${name}
            ) home.config.home.sessionVariablesPackage.text
          ) (builtins.attrNames fzfVariables);
        shellScopedVariablesAbsent = builtins.all (name: !(builtins.hasAttr name variables)) [
          "FZF_DEFAULT_COMMAND"
          "FZF_FILE_PREVIEW"
          "FZF_DIR_PREVIEW"
          "FZF_CTRL_T_COMMAND"
          "FZF_CTRL_T_OPTS"
          "FZF_ALT_C_COMMAND"
          "FZF_ALT_C_OPTS"
        ];
        previewGenerated =
          lib.trim configuredPreview != "" && lib.hasInfix (lib.trim configuredPreview) zshrc;
        fzfInit =
          lib.hasInfix "source ${fzfPackage}/share/fzf/key-bindings.zsh" zshrc
          && lib.hasInfix "source ${fzfPackage}/share/fzf/completion.zsh" zshrc;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      bashIntegration = false;
      zshIntegration = true;
      defaultOptionsConfigured = true;
      configuredVariablesExported = true;
      shellScopedVariablesAbsent = true;
      previewGenerated = true;
      fzfInit = true;
    }) homes;
  };
}
