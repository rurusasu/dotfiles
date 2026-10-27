# Exercise generated scripts against a process-boundary CLI double.
{ pkgs, code }:
{
  aerospace-workspace-cycle =
    let
      inherit (pkgs) lib;
      scripts = code.nix.modules.aerospace.aerospace-cycle {
        inherit lib;
        inherit (code.nix.home.keybindings.bindings { inherit lib; }) workspaces;
        executable = toString (
          pkgs.writeShellScript "aerospace-test-cli" ''
            case "$1" in
              list-workspaces)
                [ "$2" = --focused ] || exit 64
                [ "$FOCUSED" != FAIL ] || exit 7
                printf '%s\n' "$FOCUSED"
                ;;
              workspace) printf '%s\n' "$2" ;;
              *) exit 64 ;;
            esac
          ''
        );
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
    '';
}
