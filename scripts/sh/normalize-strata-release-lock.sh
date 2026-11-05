#!/usr/bin/env bash
# Resolve the latest feed once during updates, then retain its immutable release URL.
set -euo pipefail
flake_root=$(cd "${1:-.}" && pwd -P)
lock_file="$flake_root/flake.lock"
[[ -f $lock_file && ! -L $lock_file ]] || {
  printf 'Missing regular flake.lock: %s\n' "$lock_file" >&2
  exit 1
}
temporary=$(mktemp "$lock_file.XXXXXX")
trap 'if [[ -f $temporary ]]; then unlink "$temporary"; fi' EXIT
# shellcheck disable=SC2016 # Interpolation below is Nix syntax.
DOTFILES_FLAKE_LOCK="$lock_file" nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr '
  let
    lock = builtins.fromJSON (builtins.readFile (builtins.getEnv "DOTFILES_FLAKE_LOCK"));
    latest = "https://github.com/Niko1221/Strata/releases/latest/download/strata-feed.json";
    rootInputs = lock.nodes.${lock.root}.inputs;
    normalized =
      if !(rootInputs ? strata-release) then lock else
      let
        nodeName = rootInputs.strata-release;
        node = lock.nodes.${nodeName};
        managed = (node.original.type or null) == "file" && (node.original.url or null) == latest;
        feed = builtins.fromJSON (builtins.readFile (builtins.fetchTree node.locked).outPath);
        version = feed.app.version;
        immutable = node.locked // {
          url = "https://github.com/Niko1221/Strata/releases/download/v${version}/strata-feed.json";
        };
      in if !managed then lock else
        assert builtins.isString version && builtins.match "[0-9]+([.][0-9]+)+" version != null;
        # Verify the versioned feed has exactly the hash selected by flake update.
        builtins.seq (builtins.fetchTree immutable).outPath (lock // {
          nodes = lock.nodes // { ${nodeName} = node // { locked = immutable; }; };
        });
    # Keep the lock readable without requiring jq/Python in a fresh installer.
    render = indent: value:
      if builtins.isAttrs value then
        if value == {} then "{}" else
        "{\n" + builtins.concatStringsSep ",\n" (map (name:
          indent + "  " + builtins.toJSON name + ": " + render (indent + "  ") value.${name}
        ) (builtins.attrNames value)) + "\n" + indent + "}"
      else if builtins.isList value then
        if value == [] then "[]" else
        "[\n" + builtins.concatStringsSep ",\n" (map (entry:
          indent + "  " + render (indent + "  ") entry
        ) value) + "\n" + indent + "]"
      else builtins.toJSON value;
  in render "" normalized + "\n"
' >"$temporary"
[[ -s $temporary ]] || {
  printf 'Nix did not produce a normalized flake.lock.\n' >&2
  exit 1
}
if ! cmp -s "$lock_file" "$temporary"; then
  chmod 644 "$temporary"
  mv "$temporary" "$lock_file"
  printf 'Pinned the Strata feed URL to the selected immutable release.\n'
fi
