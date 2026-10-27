# Attribute access to repository files and Nix expressions, without per-test
# paths or a hand-maintained resource catalog. Values remain lazy.
directory:
let
  root = /. + builtins.unsafeDiscardStringContext (toString directory);
  entries = builtins.readDir root;
  names = builtins.filter (name: name != ".git") (builtins.attrNames entries);
  isNix = name: builtins.match ".*[.]nix" name != null;
  key = name: if isNix name then builtins.substring 0 (builtins.stringLength name - 4) name else name;
  children = builtins.listToAttrs (
    map (name: {
      name = name;
      value = import ./source-tree.nix (root + "/${name}");
    }) (builtins.filter (name: entries.${name} == "directory") names)
  );
  files = builtins.filter (name: entries.${name} == "regular") names;
  fileAttrs = builtins.listToAttrs (
    map (name: {
      name = key name;
      value = root + "/${name}";
    }) files
  );
  fileChildren = builtins.mapAttrs (
    name: child:
    child.files // (if builtins.hasAttr name fileAttrs then { __file = fileAttrs.${name}; } else { })
  ) children;
  codeChildren = builtins.mapAttrs (
    name: child:
    child.code // (if builtins.hasAttr name codeFiles then { __file = codeFiles.${name}; } else { })
  ) children;
  codeFiles = builtins.listToAttrs (
    map (name: {
      name = key name;
      value = import (root + "/${name}");
    }) (builtins.filter isNix files)
  );
in
{
  files = {
    __path = root;
  }
  // fileAttrs
  // fileChildren;
  code = codeFiles // codeChildren;
}
