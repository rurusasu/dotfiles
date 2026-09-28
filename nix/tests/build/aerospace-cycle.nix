# Exercise generated scripts against a process-boundary CLI double.
{ pkgs }:
let
  inherit (pkgs) lib;
  cli = pkgs.writeShellScript "aerospace-test-cli" ''
    case "$1" in
      list-workspaces)
        [ "$2" = --focused ] || exit 64
        [ "$FOCUSED" != FAIL ] || exit 7
        printf '%s\n' "$FOCUSED"
        ;;
      workspace) printf '%s\n' "$2" ;;
      *) exit 64 ;;
    esac
  '';
  contract = import ../../home/keybindings/bindings.nix { inherit lib; };
  scripts = import ../../home/keybindings/aerospace-cycle.nix {
    inherit lib;
    inherit (contract) workspaces;
    executable = toString cli;
  };
  next = pkgs.writeShellScript "workspace-next-test" scripts.next;
  prev = pkgs.writeShellScript "workspace-prev-test" scripts.prev;
in
pkgs.runCommand "aerospace-workspace-cycle-check" { } ''
  for current in 1 2 3 4 5 6 7 8 9 10; do
    test "$(FOCUSED="$current" ${next})" = "$((current % 10 + 1))"
    test "$(FOCUSED="$current" ${prev})" = "$(((current + 8) % 10 + 1))"
  done
  test "$(FOCUSED=scratchpad ${next})" = 1
  test "$(FOCUSED=scratchpad ${prev})" = 10
  test "$(FOCUSED=unknown ${next})" = 1
  if FOCUSED=FAIL ${next}; then
    echo "AeroSpace focus query failure was swallowed" >&2
    exit 1
  fi
  echo "24 workspace cycle assertions passed"
  touch "$out"
''
