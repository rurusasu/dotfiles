let
  hostModule = ../../../hosts/darwin.nix;
  homeModule = ../../../home/darwin.nix;
  hostText = builtins.readFile hostModule;
  homeText = builtins.readFile homeModule;
  hasLine =
    pattern: content:
    builtins.any (line: builtins.match ".*${pattern}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" content)
    );
in
{
  testDarwinHostProvidesFlatModule = {
    expr = builtins.pathExists hostModule;
    expected = true;
  };

  testDarwinHostUsesFlatHomeModule = {
    expr = {
      hostModuleIsFile = (builtins.readDir ../../../hosts)."darwin.nix" == "regular";
      homeModuleExists = builtins.pathExists homeModule;
      importsHomeModule = hasLine "\\.\\./home/darwin\\.nix" hostText;
    };
    expected = {
      hostModuleIsFile = true;
      homeModuleExists = true;
      importsHomeModule = true;
    };
  };

  testDarwinHostImportsRequiredModules = {
    expr =
      let
        host = import hostModule {
          pkgs = { };
          lib = { };
          inputs = { };
          sudoUser = "";
          currentUser = "test-user";
        };
      in
      {
        directModuleImports = builtins.filter builtins.isPath host.imports;
        importsDarwinTools = hasLine "import \\.\\./modules/tools\\.nix.*\\.darwin" hostText;
        homeImports = host.home-manager.users.test-user.imports;
      };
    expected = {
      directModuleImports = [ ../../../modules/docker.nix ];
      importsDarwinTools = true;
      homeImports = [ homeModule ];
    };
  };

  testDarwinFlakeConsumesFlatHostModule = {
    expr = hasLine "\\./darwin\\.nix" (builtins.readFile ../../../hosts/configurations.nix);
    expected = true;
  };

  testDarwinModulesOwnSystemAndUserOptions = {
    expr = {
      hostHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" hostText
        && hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" hostText;
      homeHasSystemOptions =
        hasLine "system[[:space:]]*=[[:space:]]*\\{" homeText
        || hasLine "homebrew[[:space:]]*=[[:space:]]*\\{" homeText;
      homeHasUserLaunchd = hasLine "launchd\\.agents" homeText;
    };
    expected = {
      hostHasSystemOptions = true;
      homeHasSystemOptions = false;
      homeHasUserLaunchd = true;
    };
  };
}
