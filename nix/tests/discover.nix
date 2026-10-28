# Test entrypoints are discovered in deterministic order. Ordinary build helpers
# stay outside the *.check.nix convention and are never treated as checks.
{
  directory,
  args ? { },
  suffix ? ".nix",
  allowEmptyFiles ? false,
}:
let
  filesUnder =
    directory:
    let
      entries = builtins.readDir directory;
    in
    builtins.concatMap (
      name:
      let
        path = directory + "/${name}";
      in
      if entries.${name} == "directory" then
        filesUnder path
      else if
        entries.${name} == "regular"

        && builtins.stringLength name >= builtins.stringLength suffix
        &&
          builtins.substring (
            builtins.stringLength name - builtins.stringLength suffix
          ) (builtins.stringLength suffix) name == suffix
      then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames entries);
  files = filesUnder directory;
  load =
    file:
    let
      imported = import file;
      value =
        if builtins.isFunction imported then
          imported (builtins.intersectAttrs (builtins.functionArgs imported) args)
        else
          imported;
    in
    if !builtins.isAttrs value then
      throw "Test entrypoint ${toString file} must return an attribute set."
    else if !allowEmptyFiles && value == { } then
      throw "Test entrypoint ${toString file} contains zero tests."
    else
      value;
  values = builtins.foldl' (
    collected: file:
    let
      next = load file;
      duplicate = builtins.attrNames (builtins.intersectAttrs collected next);
    in
    if duplicate != [ ] then
      throw "Duplicate test/check names in ${toString file}: ${builtins.concatStringsSep ", " duplicate}"
    else
      collected // next
  ) { } files;
in
{
  inherit files;
  values =
    if values == { } then
      throw "Test discovery under ${toString directory} found zero tests/checks."
    else
      values;
}
