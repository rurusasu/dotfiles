let
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
    in
    builtins.substring 0 (builtins.stringLength rootText) (toString path) == rootText;

  contains = pattern: content: builtins.length (builtins.split pattern content) > 1;

  # Inspect declarations without evaluating caller modules. Mask strings first
  # so example text cannot be mistaken for an import declaration.
  containsImport =
    target: content:
    builtins.match ".*imports[[:space:]]*=[[:space:]]*\\[[^]]*([^]]*/|[.]/)${target}\\.nix.*" (
      builtins.concatStringsSep " " (
        builtins.filter builtins.isString (
          builtins.split "#[^[:cntrl:]]*"
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
                    inherit (state) text;
                    inComment = builtins.head token == "/*";
                  }
              )
              {
                inComment = false;
                text = "";
              }
              (
                builtins.split "(/\\*|\\*/)" (
                  builtins.concatStringsSep "\n" (
                    builtins.filter builtins.isString (builtins.split "\"[^\"]*\"|''[^']*''" content)
                  )
                )
              )
            ).text
        )
      )
    ) != null;

  entryModules = [
    ../../../home/darwin.nix
    ../../../hosts/default.nix
    ../../../home/wsl.nix
  ];

  homeLayout = {
    required = [
      ../../../home/README.md
      ../../../home/common.nix
      ../../../home/darwin.nix
      ../../../hosts/default.nix
      ../../../home/wsl.nix
    ];
    removed = [
      ../../../home/default.nix
      ../../../home/users
      ../../../home/nixos.nix
      ../../../home/linux.nix
    ];
  };

in
{
  testHomeManagerUsesSharedUserAndHostEntrypointLayout = {
    expr = {
      required = builtins.map builtins.pathExists homeLayout.required;
      removed = builtins.map builtins.pathExists homeLayout.removed;
      hostDirectories = builtins.filter (name: (builtins.readDir ../../../hosts).${name} == "directory") (
        builtins.attrNames (builtins.readDir ../../../hosts)
      );
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
        false
        false
      ];
      hostDirectories = [ ];
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
    expr = builtins.map (os: containsImport os (builtins.readFile ../../../home/common.nix)) [
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

  testOnlyHostHomeModulesImportCommonOutsideHome = {
    expr =
      builtins.filter
        (path: !(builtins.elem path entryModules) && containsImport "common" (builtins.readFile path))
        (
          # Test fixtures and expected module lists are not production imports.
          builtins.filter (path: !(isUnder ../../../home path) && !(isUnder ../.. path)) (filesUnder ../../..)
        );
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
