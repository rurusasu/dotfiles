{ homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
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
    expr = map (
      home:
      let
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" home.config.programs.zsh.dotDir}/.zshrc".text;
      in
      {
        guarded = lib.hasInfix "if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then" zshrc;
        functionDefined = lib.hasInfix "rfg() {" zshrc;
        reloadStart = lib.hasInfix "start:reload:rg --line-number --no-heading --color=always -- {q} || true" zshrc;
        reloadChange = lib.hasInfix "change:reload:rg --line-number --no-heading --color=always -- {q} || true" zshrc;
        preview = lib.hasInfix "--preview 'bat --color=always --highlight-line {2} -- {1}'" zshrc;
        editorInvocation = lib.hasInfix ''''${EDITOR:-vi} "+$line" "$file"'' zshrc;
      }
    ) homes;
    expected = map (_: {
      guarded = true;
      functionDefined = true;
      reloadStart = true;
      reloadChange = true;
      preview = true;
      editorInvocation = true;
    }) homes;
  };
}
