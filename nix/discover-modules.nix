# Discover only module entrypoints for the requested evaluation scope.
# Attribute names give deterministic order; symlinks and ordinary Nix helpers
# are deliberately excluded.
scope: directory:
let
  entries = builtins.readDir directory;
  discover = import ./discover-modules.nix;
in
builtins.concatMap (
  name:
  let
    path = directory + "/${name}";
  in
  if entries.${name} == "directory" then
    discover scope path
  else if
    entries.${name} == "regular"
    && (name == "${scope}.nix" || builtins.match ".*[.]${scope}[.]nix" name != null)
  then
    [ path ]
  else
    [ ]
) (builtins.attrNames entries)
