{ pkgs }:
let
  inherit (pkgs) lib;

  installedZsh = pkgs.writeShellScriptBin "zsh" "exit 0";
  missingZsh = pkgs.runCommand "missing-zsh" { meta.mainProgram = "zsh"; } ''
    mkdir -p "$out/bin"
  '';
  nonExecutableZsh = pkgs.runCommand "non-executable-zsh" { meta.mainProgram = "zsh"; } ''
    mkdir -p "$out/bin"
    printf 'not executable\n' > "$out/bin/zsh"
    chmod 644 "$out/bin/zsh"
  '';

  idDouble = pkgs.writeShellScriptBin "id" ''
    set -eu
    [[ "$#" = 2 && "$1" = -u && "$2" = test-user ]] || exit 90
    [[ "$TEST_USER_EXISTS" = 1 ]] || exit 1
    printf '%s\n' "$TEST_UID"
    [[ "$TEST_ID_MODE" != error-with-output ]] || exit 1
  '';
  dsclDouble = pkgs.writeShellScriptBin "dscl" ''
    set -eu
    [[ "$#" -ge 4 && "$1" = . && "$4" = UserShell ]] || exit 90
    case "$3" in
      /Users/test-user) record="$TEST_STATE/test-user" ;;
      /Users/root) record="$TEST_STATE/root" ;;
      /Users/other-user) record="$TEST_STATE/other-user" ;;
      *) exit 91 ;;
    esac

    case "$2" in
      -read)
        [[ "$#" = 4 ]] || exit 92
        reads="$(cat "$TEST_STATE/reads")"
        reads=$((reads + 1))
        printf '%s\n' "$reads" > "$TEST_STATE/reads"
        case "$TEST_READ_MODE" in
          error) exit 1 ;;
          malformed) printf 'UnexpectedAttribute: /bin/bash\n'; exit 0 ;;
          empty) printf 'UserShell: \n'; exit 0 ;;
          multiline) printf 'UserShell: /bin/bash\nUnexpectedAttribute: value\n'; exit 0 ;;
          readback-error) [[ "$reads" = 1 ]] || exit 1 ;;
        esac
        printf 'UserShell: %s\n' "$(cat "$record")"
        if [[ "$TEST_READ_MODE" = readback-error-with-output && "$reads" != 1 ]]; then
          exit 1
        fi
        ;;
      -change)
        [[ "$#" = 6 ]] || exit 93
        printf '%s\n' "$3" >> "$TEST_STATE/writes"
        [[ "$TEST_WRITE_MODE" != error ]] || exit 1
        [[ "$(cat "$record")" = "$5" ]] || exit 94
        if [[ "$TEST_WRITE_MODE" != noop ]]; then
          printf '%s\n' "$6" > "$record"
        fi
        ;;
      *) exit 95 ;;
    esac
  '';

  # Execute the production Nix text, replacing only macOS command/file
  # boundaries. No real account or host /etc/shells is read or modified.
  activationFor =
    name: zsh:
    let
      host = import ../../hosts/darwin/configuration.nix {
        pkgs = pkgs // { inherit zsh; };
        inherit lib;
        inputs = { };
        sudoUser = "test-user";
        currentUser = "root";
        dotfilesWithHermes = false;
        dotfilesWithDocker = false;
        dotfilesWithOllama = false;
      };
    in
    pkgs.writeText "darwin-default-shell-${name}" (
      lib.replaceStrings
        [ "/usr/bin/id" "/usr/bin/dscl" "/etc/shells" ]
        [ "${idDouble}/bin/id" "${dsclDouble}/bin/dscl" "$TEST_STATE/shells" ]
        host.system.activationScripts.defaultUserShell.text
    );
  installedActivation = activationFor "installed" installedZsh;
  missingActivation = activationFor "missing" missingZsh;
  nonExecutableActivation = activationFor "non-executable" nonExecutableZsh;
in
pkgs.runCommand "darwin-default-shell-tests" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -euo pipefail
  tests=0
  target=${lib.escapeShellArg (lib.getExe installedZsh)}
  # Activation selects the module's sudoUser, not these process identities.
  export USER=root SUDO_USER=other-user

  fail() {
    printf 'FAIL: %s: %s\n' "$case_name" "$1" >&2
    cat "$TEST_STATE/output" >&2
    exit 1
  }

  reset_state() {
    case_name="$1"
    export TEST_STATE="$TMPDIR/$case_name"
    export TEST_UID=501 TEST_USER_EXISTS=1 TEST_ID_MODE=normal TEST_READ_MODE=normal TEST_WRITE_MODE=normal
    mkdir -p "$TEST_STATE"
    printf '/bin/bash\n' > "$TEST_STATE/test-user"
    printf '/bin/sh\n' > "$TEST_STATE/root"
    printf '/bin/zsh\n' > "$TEST_STATE/other-user"
    printf '%s\n' "$target" > "$TEST_STATE/shells"
    printf '0\n' > "$TEST_STATE/reads"
    : > "$TEST_STATE/writes"
    : > "$TEST_STATE/output"
  }

  run_activation() {
    if ${pkgs.bash}/bin/bash -e "$1" > "$TEST_STATE/output" 2>&1; then
      [[ "$2" = success ]] || fail 'activation unexpectedly succeeded'
    else
      [[ "$2" = failure ]] || fail 'activation unexpectedly failed'
    fi
  }

  assert_other_users_unchanged() {
    [[ "$(cat "$TEST_STATE/root")" = /bin/sh ]] || fail 'root was modified'
    [[ "$(cat "$TEST_STATE/other-user")" = /bin/zsh ]] || fail 'another user was modified'
  }

  assert_accounts_unchanged() {
    [[ "$(cat "$TEST_STATE/test-user")" = /bin/bash ]] || fail 'selected user was modified'
    assert_other_users_unchanged
  }

  assert_no_change() {
    assert_accounts_unchanged
    [[ ! -s "$TEST_STATE/writes" ]] || fail 'a write was attempted before preconditions passed'
  }

  pass() {
    tests=$((tests + 1))
    printf 'ok %s - %s\n' "$tests" "$case_name"
  }

  reset_state selected-user
  run_activation ${installedActivation} success
  [[ "$(cat "$TEST_STATE/test-user")" = "$target" ]] || fail 'selected user did not get zsh'
  [[ "$(cat "$TEST_STATE/writes")" = /Users/test-user ]] || fail 'expected one write to the selected user'
  [[ "$(cat "$TEST_STATE/reads")" = 2 ]] || fail 'successful change was not read back'
  assert_other_users_unchanged
  pass

  case_name=idempotence
  : > "$TEST_STATE/writes"
  run_activation ${installedActivation} success
  [[ "$(cat "$TEST_STATE/test-user")" = "$target" ]] || fail 'existing zsh was changed'
  [[ ! -s "$TEST_STATE/writes" ]] || fail 'repeated activation attempted a write'
  assert_other_users_unchanged
  pass

  reset_state missing-shell
  printf '%s\n' ${lib.escapeShellArg (lib.getExe missingZsh)} > "$TEST_STATE/shells"
  run_activation ${missingActivation} failure
  assert_no_change
  pass

  reset_state non-executable-shell
  printf '%s\n' ${lib.escapeShellArg (lib.getExe nonExecutableZsh)} > "$TEST_STATE/shells"
  run_activation ${nonExecutableActivation} failure
  assert_no_change
  pass

  reset_state unregistered-shell
  # A substring match must not count as registration in /etc/shells.
  printf '%s-extra\n' "$target" > "$TEST_STATE/shells"
  run_activation ${installedActivation} failure
  assert_no_change
  pass

  reset_state unknown-user
  export TEST_USER_EXISTS=0
  run_activation ${installedActivation} failure
  assert_no_change
  pass

  reset_state uid-zero
  export TEST_UID=0
  run_activation ${installedActivation} failure
  assert_no_change
  pass

  reset_state id-error-with-output
  export TEST_ID_MODE=error-with-output
  run_activation ${installedActivation} failure
  assert_no_change
  pass

  for mode in error malformed empty multiline; do
    reset_state "read-$mode"
    export TEST_READ_MODE="$mode"
    run_activation ${installedActivation} failure
    # Malformed values may be rejected by dscl's compare-and-set itself.
    # Either way, no account may change, and read errors must stop before it.
    assert_accounts_unchanged
    if [[ "$mode" = error ]]; then
      [[ ! -s "$TEST_STATE/writes" ]] || fail 'read failure attempted a write'
    fi
    pass
  done

  for mode in error noop; do
    reset_state "write-$mode"
    export TEST_WRITE_MODE="$mode"
    run_activation ${installedActivation} failure
    [[ "$(cat "$TEST_STATE/test-user")" = /bin/bash ]] || fail 'failed write changed the user'
    [[ "$(cat "$TEST_STATE/writes")" = /Users/test-user ]] || fail 'expected one attempted write'
    assert_other_users_unchanged
    pass
  done

  for mode in readback-error readback-error-with-output; do
    reset_state "$mode"
    export TEST_READ_MODE="$mode"
    run_activation ${installedActivation} failure
    [[ "$(cat "$TEST_STATE/test-user")" = "$target" ]] || fail 'readback failure fixture did not apply the change'
    [[ "$(cat "$TEST_STATE/writes")" = /Users/test-user ]] || fail 'expected one attempted write'
    assert_other_users_unchanged
    pass
  done

  [[ "$tests" -eq 16 ]] || fail 'unexpected test count'
  mkdir -p "$out"
  printf '%s tests passed\n' "$tests" > "$out/result"
''
