{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  rc =
    home:
    let
      dotDir = home.config.programs.zsh.dotDir;
      homeDir = home.config.home.homeDirectory;
    in
    home.config.home.file."${
      if dotDir == homeDir then "." else lib.removePrefix "${homeDir}/" dotDir
    }/.zshrc".text;
  line = prefix: text: lib.findFirst (lib.hasPrefix prefix) null (lib.splitString "\n" text);
in
{
  testZshEnabled = {
    expr = map (home: home.config.programs.zsh.enable) homes;
    expected = map (_: true) homes;
  };

  testZshConfiguration = {
    expr = map (home: {
      historySize = line "HISTSIZE=" (rc home);
      historySave = line "SAVEHIST=" (rc home);
      historyPath = line "HISTFILE=" (rc home);
      options = lib.hasInfix (builtins.unsafeDiscardStringContext (home.config.lib.zsh.define "set_opts" home.config.programs.zsh.setOptions)) (
        rc home
      );
      customInit =
        lib.hasInfix "bindkey '^?' backward-delete-char" (rc home)
        && lib.hasInfix "add-zsh-hook precmd __disable_mouse_reporting" (rc home);
      aliases = lib.mapAttrsToList (
        name: value:
        lib.hasInfix (builtins.unsafeDiscardStringContext "alias -- ${lib.escapeShellArg name}=${lib.escapeShellArg value}") (
          rc home
        )
      ) home.config.programs.zsh.shellAliases;
    }) homes;
    expected = map (
      home:
      let
        zsh = home.config.programs.zsh;
      in
      {
        historySize = ''HISTSIZE="${toString zsh.history.size}"'';
        historySave = ''SAVEHIST="${toString zsh.history.save}"'';
        historyPath = ''HISTFILE="${lib.removeSuffix "/" zsh.history.path}"'';
        options = true;
        customInit = true;
        aliases = lib.mapAttrsToList (_: _: true) zsh.shellAliases;
      }
    ) homes;
  };

  testZshDotDirectory = {
    expr = map (home: home.config.home.file.".zshenv".text) homes;
    expected = map (home: ''
      source ${lib.escapeShellArg "${home.config.programs.zsh.dotDir}/.zshenv"}
    '') homes;
  };

  testZshCompletion = {
    expr = map (
      home:
      let
        zsh = home.config.programs.zsh;
      in
      {
        enabled = zsh.enableCompletion;
        packageCompletions = lib.hasInfix "$profile/share/zsh/site-functions" (rc home);
        plugins = lib.hasInfix (builtins.unsafeDiscardStringContext (
          home.config.lib.zsh.define "plugins" (map (plugin: "${plugin.name}/${plugin.file}") zsh.plugins)
        )) (rc home);
        pluginSources = map (
          plugin:
          toString
            home.config.home.file."${
              zsh.dotDir + lib.optionalString (zsh.dotDir == home.config.home.homeDirectory) "/.zsh" + "/plugins"
            }/${plugin.name}".source
        ) zsh.plugins;
      }
    ) homes;
    expected = map (
      home:
      let
        zsh = home.config.programs.zsh;
      in
      {
        enabled = true;
        packageCompletions = zsh.enableCompletion;
        plugins = true;
        pluginSources = map (plugin: toString plugin.src) zsh.plugins;
      }
    ) homes;
  };
}
