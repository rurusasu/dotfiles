# Stable global numeric order, including empty workspaces, excluding scratchpad.
{
  lib,
  executable,
  workspaces,
}:
let
  names = map toString workspaces;
  count = builtins.length names;
  script = offset: fallback: ''
    set -eu
    current="$(${lib.escapeShellArg executable} list-workspaces --focused)"
    case "$current" in
      ${lib.concatStringsSep "\n" (
        lib.imap0 (
          index: name:
          "${lib.escapeShellArg name}) target=${
            lib.escapeShellArg (builtins.elemAt names (lib.mod (index + offset) count))
          } ;;"
        ) names
      )}
      *) target=${lib.escapeShellArg fallback} ;;
    esac
    exec ${lib.escapeShellArg executable} workspace "$target"
  '';
in
assert count > 0;
{
  next = script 1 (builtins.head names);
  prev = script (count - 1) (lib.last names);
}
