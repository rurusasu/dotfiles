let
  nixRoot = ../..;
  homeRoot = ../../home;
  testsRoot = ./.;

  filesUnder =
    dir:
    let
      entries = builtins.readDir dir;
    in
    builtins.concatLists (
      map (
        name:
        let
          path = dir + "/${name}";
        in
        if entries.${name} == "directory" then
          filesUnder path
        else if builtins.match ".*\\.nix" name != null then
          [ path ]
        else
          [ ]
      ) (builtins.attrNames entries)
    );

  isUnder =
    root: path:
    let
      rootText = toString root;
      pathText = toString path;
    in
    builtins.substring 0 (builtins.stringLength rootText) pathText == rootText;

  contains = pattern: content: builtins.length (builtins.split pattern content) > 1;

  # External callers cannot be evaluated as Home Manager modules here, so
  # inspect only import declarations after removing Nix line comments.
  stripLineComments = content:
    builtins.replaceStrings [ "\n" "\r" ] [ " " " " ] (
      builtins.concatStringsSep " " (builtins.split "#[^\\n]*" content)
    );
  containsImport =
    target: content:
    builtins.match ".*imports[[:space:]]*=[[:space:]]*\\[[^]]*([^]]*/|[.]/)${target}\\.nix.*" (
      stripLineComments content
    ) != null;

  moduleImports = path: (import path { pkgs = { }; lib = { }; inputs = { }; }).imports or [ ];
  importsPath = path: target: builtins.elem target (moduleImports path);

  entryModules = [
    ../../home/darwin.nix
    ../../home/linux.nix
    ../../home/wsl.nix
  ];

  homeLayout = {
    required = [
      ../../home/README.md
      ../../home/common.nix
      ../../home/darwin.nix
      ../../home/linux.nix
      ../../home/wsl.nix
    ];
    removed = [
      ../../home/default.nix
      ../../home/users
    ];
  };

  externalNixFiles = builtins.filter (path: !(isUnder homeRoot path) && !(isUnder testsRoot path)) (
    filesUnder nixRoot
  );

  externalDirectImports = builtins.filter (
    path: containsImport "common" (builtins.readFile path)
  ) externalNixFiles;
in
{
  testHomeManagerUsesCanonicalFlatOSModuleLayout = {
    expr = {
      required = builtins.map builtins.pathExists homeLayout.required;
      removed = builtins.map builtins.pathExists homeLayout.removed;
    };
    expected = {
      required = [
        true
        true
        true
        true
        true
      ];
      removed = [
        false
        false
      ];
    };
  };

  testOSHomeEntrypointsImportCommon = {
    expr = builtins.map (path: importsPath path (../../home/common.nix)) entryModules;
    expected = [
      true
      true
      true
    ];
  };

  testSharedHomeModuleDoesNotImportOSModules = {
    expr = builtins.map (os: containsImport os (builtins.readFile ../../home/common.nix)) [
      "darwin"
      "linux"
      "wsl"
    ];
    expected = [
      false
      false
      false
    ];
  };

  testExternalCallersDoNotImportCommon = {
    expr = externalDirectImports;
    expected = [ ];
  };

  testCommentOnlyCommonMentionIsNotAnImport = {
    expr = [
      (containsImport "common" "# imports = [ ./common.nix ];")
      (containsImport "common" ''message = "./common.nix";'')
      (containsImport "common" "imports = [ ../home/common.nix ];")
    ];
    expected = [ false false true ];
  };
}
