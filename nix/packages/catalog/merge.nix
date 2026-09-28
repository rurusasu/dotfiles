# Reject duplicate ownership before combining category definitions.
{ lib }:
categories:
lib.foldlAttrs (
  accumulated: category: entries:
  let
    duplicates = lib.intersectLists (builtins.attrNames accumulated) (builtins.attrNames entries);
    misplaced = builtins.filter (name: entries.${name}.category != category) (
      builtins.attrNames entries
    );
  in
  if duplicates != [ ] then
    throw "package catalog: duplicate IDs in ${category}: ${lib.concatStringsSep ", " duplicates}"
  else if misplaced != [ ] then
    throw "package catalog: category mismatch in ${category}: ${lib.concatStringsSep ", " misplaced}"
  else
    accumulated // entries
) { } categories
