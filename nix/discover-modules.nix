# A module is a default.nix entrypoint. Home Manager is the default scope;
# generic nixos/darwin/system directories select the OS evaluation scope.
scope: root:
let
  scopes = [
    "home-manager"
    "nixos"
    "darwin"
    "system"
  ];
  collect =
    currentScope: directory:
    let
      entries = builtins.readDir directory;
    in
    builtins.concatMap (
      name:
      let
        path = directory + "/${name}";
      in
      if entries.${name} == "directory" then
        collect (if builtins.elem name scopes then name else currentScope) path
      else if entries.${name} == "regular" && name == "default.nix" && currentScope == scope then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames entries);
in
collect "home-manager" root
