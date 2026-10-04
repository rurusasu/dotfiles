{ pkgs }:
let
  inherit (pkgs) lib;
  host = import ../../hosts/darwin/configuration.nix {
    inherit pkgs lib;
    inputs = { };
    sudoUser = "test-user";
    currentUser = "root";
    dotfilesWithHermes = false;
    dotfilesWithDocker = false;
    dotfilesWithOllama = false;
  };
  commandDouble = pkgs.writeShellScript "default-shell-command" ''
    set -eu
    mode="$1"; shift
    if [[ "$mode" = id ]]; then
      [[ "$#" = 2 && "$1" = -u && "$2" = test-user ]] || exit 90
      [[ "$scenario" != unknown-user ]] || exit 1
      if [[ "$scenario" = uid-zero ]]; then echo 0; else echo 501; fi
      exit 0
    fi
    [[ "$mode" = dscl && "$#" -ge 4 ]] || exit 90
    [[ "$1" = . && "$3" = /Users/test-user && "$4" = UserShell ]] || exit 90
    case "$2" in
      -read)
        [[ "$#" = 4 && "$scenario" != read-error ]] || exit 1
        printf 'UserShell: %s\n' "$(cat "$FIXTURE/current")"
        if [[ "$scenario" = verify-error && -s "$FIXTURE/writes" ]]; then exit 1; fi
        ;;
      -change)
        [[ "$#" = 6 && "$(cat "$FIXTURE/current")" = "$5" ]] || exit 90
        [[ "$scenario" != write-error ]] || exit 1
        [[ "$scenario" != write-noop ]] || exit 0
        printf '%s\n' "$6" > "$FIXTURE/current"
        echo changed >> "$FIXTURE/writes"
        ;;
      *) exit 90 ;;
    esac
  '';
  # Keep the emitted activation intact except for macOS command/file boundaries.
  activation = pkgs.writeText "darwin-default-shell-activation" (
    lib.replaceStrings
      [
        (lib.escapeShellArg "/bin/zsh")
        "/usr/bin/id"
        "/usr/bin/dscl"
        "/usr/bin/grep"
        "/etc/shells"
      ]
      [
        ''"$FIXTURE/zsh"''
        "${commandDouble} id"
        "${commandDouble} dscl"
        "${pkgs.gnugrep}/bin/grep"
        ''"$FIXTURE/shells"''
      ]
      host.system.activationScripts.defaultUserShell.text
  );
in
pkgs.runCommand "darwin-default-shell-tests" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -euo pipefail
  export FIXTURE="$TMPDIR/account" USER=root SUDO_USER=other-user
  mkdir -p "$FIXTURE"
  tests=0
  for scenario in selected-user already-correct missing-shell unregistered-shell \
    unknown-user uid-zero read-error write-error write-noop verify-error; do
    export scenario
    printf '/bin/bash\n' > "$FIXTURE/current"
    : > "$FIXTURE/writes"
    ln -sf ${pkgs.bash}/bin/bash "$FIXTURE/zsh"
    printf '%s\n' "$FIXTURE/zsh" > "$FIXTURE/shells"
    expected_status=failure
    expected_shell=/bin/bash
    expected_writes=
    case "$scenario" in
      selected-user|verify-error)
        expected_shell="$FIXTURE/zsh"; expected_writes=changed
        if [[ "$scenario" = selected-user ]]; then expected_status=success; fi
        ;;
      already-correct)
        expected_status=success; expected_shell="$FIXTURE/zsh"
        printf '%s\n' "$expected_shell" > "$FIXTURE/current"
        ;;
      missing-shell) rm "$FIXTURE/zsh" ;;
      unregistered-shell) printf '%s-extra\n' "$FIXTURE/zsh" > "$FIXTURE/shells" ;;
    esac
    if ${pkgs.bash}/bin/bash -e ${activation} > "$FIXTURE/output" 2>&1; then
      status=success
    else
      status=failure
    fi
    if [[ "$status" != "$expected_status" ||
      "$(cat "$FIXTURE/current")" != "$expected_shell" ||
      "$(cat "$FIXTURE/writes")" != "$expected_writes" ]]; then
      echo "FAIL: $scenario" >&2
      cat "$FIXTURE/output" >&2
      exit 1
    fi
    tests=$((tests + 1))
    echo "ok $tests - $scenario"
  done
  [[ "$tests" = 10 ]]
  mkdir -p "$out"
  printf '%s tests passed\n' "$tests" > "$out/result"
''
