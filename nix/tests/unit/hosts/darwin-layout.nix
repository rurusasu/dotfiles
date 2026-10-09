let
  entrypoint = ../../../hosts/aarch64-darwin/default.nix;
  configuration = ../../../hosts/aarch64-darwin/configuration.nix;
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
        inherit ((import entrypoint { })) imports;
      in
      builtins.all (module: builtins.elem module imports) [
        configuration
        ../../../hosts/aarch64-darwin/platform.nix
        ../../../hosts/aarch64-darwin/system.nix
      ];
    expected = true;
  };

  testDarwinFlakeConsumesHostDirectory = {
    expr =
      let
        flakeText = builtins.readFile ../../../hosts/configurations.nix;
      in
      hasLine "\\./aarch64-darwin" flakeText;
    expected = true;
  };

  testDarwinSystemOptionsBelongToConfiguration = {
    expr = {
      entrypointHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" entrypointText
        || hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" entrypointText
        || hasLine "launchd\\.user" entrypointText;
      configurationHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" configurationText
        && hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" configurationText;
    };
    expected = {
      entrypointHasSystemOptions = false;
      configurationHasSystemOptions = true;
    };
  };
}
