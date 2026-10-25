{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  rc =
    home:
    let
      dotDir = home.config.programs.zsh.dotDir;
      homeDir = home.config.home.homeDirectory;
      relativeDir = if dotDir == homeDir then "." else lib.removePrefix "${homeDir}/" dotDir;
    in
    home.config.home.file."${relativeDir}/.zshrc".text;
  line = prefix: text: lib.findFirst (lib.hasPrefix prefix) null (lib.splitString "\n" text);
  userSources =
    home:
    let
      userZsh = import ../../../home/shells/zsh { inherit (home) config; };
    in
    builtins.filter (lib.hasPrefix "source ") (lib.splitString "\n" userZsh.programs.zsh.initContent);
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
      sources = builtins.filter (source: builtins.elem source (userSources home)) (
        lib.splitString "\n" (rc home)
      );
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
        sources = userSources home;
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
        pluginsDir =
          zsh.dotDir + lib.optionalString (zsh.dotDir == home.config.home.homeDirectory) "/.zsh" + "/plugins";
      in
      {
        enabled = zsh.enableCompletion;
        packageCompletions = lib.hasInfix "$profile/share/zsh/site-functions" (rc home);
        plugins = lib.hasInfix (builtins.unsafeDiscardStringContext (
          home.config.lib.zsh.define "plugins" (map (plugin: "${plugin.name}/${plugin.file}") zsh.plugins)
        )) (rc home);
        pluginSources = map (
          plugin: toString home.config.home.file."${pluginsDir}/${plugin.name}".source
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
