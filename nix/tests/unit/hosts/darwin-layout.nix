let
  entrypoint = ../../../hosts/darwin/default.nix;
  configuration = ../../../hosts/darwin/configuration.nix;
  entrypointText = builtins.readFile entrypoint;
  configurationText =
    if builtins.pathExists configuration then builtins.readFile configuration else "";
  hasLine =
    pattern: content:
    builtins.any (line: builtins.match ".*${pattern}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" content)
    );
in
{
  testDarwinHostProvidesConfigurationFile = {
    expr = builtins.pathExists configuration;
    expected = true;
  };

  testDarwinHostEntrypointImportsConfiguration = {
    expr =
      hasLine "imports[[:space:]]*=[[:space:]]*\\[" entrypointText
      && hasLine "\\./configuration\\.nix" entrypointText;
    expected = true;
  };

  testDarwinHostEntrypointImportsRequiredModules = {
    expr =
      let
        imports = (import entrypoint { }).imports;
      in
      builtins.all (module: builtins.elem module imports) [
        configuration
        ../../../modules/darwin
        ../../../hosts/darwin/system.nix
      ];
    expected = true;
  };

  testDarwinFlakeConsumesHostDirectory = {
    expr =
      let
        flakeText = builtins.readFile ../../../flakes/darwin.nix;
      in
      hasLine "\\.\\./hosts/darwin" flakeText;
    expected = true;
  };

  testDarwinSystemOptionsBelongToConfiguration = {
    expr = {
      entrypointHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" entrypointText
        || hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" entrypointText
        || hasLine "launchd\.user" entrypointText;
      configurationHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" configurationText
        && hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" configurationText
        && hasLine "launchd\.user" configurationText;
    };
    expected = {
      entrypointHasSystemOptions = false;
      configurationHasSystemOptions = true;
    };
  };
}
