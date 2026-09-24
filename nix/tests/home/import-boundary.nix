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

  # Inspect declarations without evaluating caller modules. Mask strings first
  # so example text cannot be mistaken for an import declaration.
  stripStrings =
    content:
    builtins.concatStringsSep " " (
      builtins.filter builtins.isString (builtins.split "\"[^\"]*\"|''[^']*''" content)
    );
  stripBlockComments =
    content:
    (builtins.foldl'
      (
        state: token:
        if builtins.isString token then
          {
            inherit (state) inComment;
            text = state.text + (if state.inComment then "" else token);
          }
        else
          {
            text = state.text;
            inComment = builtins.head token == "/*";
          }
      )
      {
        inComment = false;
        text = "";
      }
      (builtins.split "(/\\*|\\*/)" content)
    ).text;
  stripLineComments =
    content:
    let
      uncommented = stripBlockComments (stripStrings content);
    in
    builtins.replaceStrings [ "\n" "\r" ] [ " " " " ] (
      builtins.concatStringsSep " " (
        builtins.filter builtins.isString (builtins.split "#[^\\n]*" uncommented)
      )
    );
  containsImport =
    target: content:
    builtins.match ".*imports[[:space:]]*=[[:space:]]*\\[[^]]*([^]]*/|[.]/)${target}\\.nix.*" (
      stripLineComments content
    ) != null;

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
    expr = builtins.map (path: containsImport "common" (builtins.readFile path)) entryModules;
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
      (containsImport "common" ''message = "imports = [ ./common.nix ]";'')
      (containsImport "common" ''
        /* imports = [ ./common.nix ];
         * still a comment */
        { }
      '')
      (containsImport "common" "imports = [ ../home/common.nix ];")
      (containsImport "common" ''
        imports = [
          # shared module
          ./common.nix
        ];
      '')
    ];
    expected = [
      false
      false
      false
      true
      true
    ];
  };
}
