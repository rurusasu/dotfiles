#!/usr/bin/env bash
# Update release inputs through immutable URLs and publish the complete lock atomically.
set -euo pipefail
flake_root=$(cd "${1:?A flake root is required}" && pwd -P)
case "${2:-git}" in
git) flake_ref="$flake_root" ;;
path) flake_ref="path:$flake_root" ;;
*)
  printf 'Invalid flake source: %s (expected git or path).\n' "$2" >&2
  exit 1
  ;;
esac
lock_file="$flake_root/flake.lock"
[[ -f $lock_file && ! -L $lock_file ]] || {
  printf 'Missing regular flake.lock: %s\n' "$lock_file" >&2
  exit 1
}
updated=$(mktemp "$lock_file.update.XXXXXX")
temporary=
trap 'if [[ -f $updated ]]; then unlink "$updated"; fi; if [[ -f $temporary ]]; then unlink "$temporary"; fi' EXIT
temporary=$(mktemp "$lock_file.normalized.XXXXXX")
nix_options=(--accept-flake-config --extra-experimental-features 'nix-command flakes')
# Read the declaration without evaluating outputs or fetching the old mutable DMG.
dia_url=$(DOTFILES_FLAKE_ROOT="$flake_root" nix "${nix_options[@]}" eval --refresh --impure --raw --expr '
  let
    declaration = (import ((builtins.getEnv "DOTFILES_FLAKE_ROOT") + "/flake.nix")).inputs.dia or {};
    managed = (declaration.type or null) == "file"
      && (declaration.url or null) == "https://releases.diabrowser.com/release/Dia-latest.dmg";
    feed = builtins.readFile (builtins.fetchTree {
      type = "file";
      url = "https://releases.diabrowser.com/BoostBrowser-updates.xml";
    }).outPath;
    # Appcast order is newest first; full-release ZIPs exclude Sparkle deltas.
    versions = builtins.filter builtins.isList (builtins.split
      "<enclosure[^>]*[[:space:]]url=\"https://releases[.]diabrowser[.]com/release/Dia-([0-9.]+-[0-9]+)[.]zip\"" feed);
  in if !managed then "" else
    assert versions != [];
    "https://releases.diabrowser.com/release/Dia-" + builtins.head (builtins.head versions) + ".dmg"
')
overrides=()
if [[ -n $dia_url ]]; then
  overrides=(--override-input dia "file+$dia_url")
fi
nix "${nix_options[@]}" flake update --flake "$flake_ref" \
  --reference-lock-file "$lock_file" --output-lock-file "$updated" ${overrides[@]+"${overrides[@]}"}
[[ -s $updated ]] || {
  printf 'Nix did not produce an updated flake.lock.\n' >&2
  exit 1
}
# shellcheck disable=SC2016 # Interpolation below is Nix syntax.
DOTFILES_FLAKE_LOCK="$updated" DOTFILES_DIA_URL="$dia_url" nix "${nix_options[@]}" eval --impure --raw --expr '
  let
    updated = builtins.fromJSON (builtins.readFile (builtins.getEnv "DOTFILES_FLAKE_LOCK"));
    diaUrl = builtins.getEnv "DOTFILES_DIA_URL";
    lock = if diaUrl == "" then updated else
      let
        nodeName = updated.nodes.${updated.root}.inputs.dia;
        node = updated.nodes.${nodeName};
      in assert node.locked.url == diaUrl;
        updated // {
          nodes = updated.nodes // { ${nodeName} = node // {
            original = node.original // {
              type = "file";
              url = "https://releases.diabrowser.com/release/Dia-latest.dmg";
            };
          }; };
        };
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
  printf 'Updated flake inputs with immutable release URLs.\n'
fi
