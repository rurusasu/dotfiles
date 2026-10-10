{ inputs, pkgs }:
let
  darwin = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      ../../modules/docker.nix
      {
        system.primaryUser = "test-user";
        users.users.test-user.home = "/Users/test-user";
        homebrew.enable = true;
        homebrew.casks = [ "docker-desktop" ];
      }
    ];
  };
  activation = pkgs.writeText "docker-desktop-activation" darwin.config.system.activationScripts.postActivation.text;
in
pkgs.runCommand "docker-desktop-activation-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.shellcheck
    ];
  }
  ''
    shellcheck --shell=bash ${activation}
    export TEST_HOME="$TMPDIR/home" COMMAND_LOG="$TMPDIR/commands.log"
    mkdir -p "$TEST_HOME" "$TMPDIR/bin" "$TMPDIR/Applications/Docker.app/Contents/MacOS" "$TMPDIR/usr/local/bin" "$TMPDIR/sbin"
    touch "$COMMAND_LOG" "$TMPDIR/sbin/md5"
    chmod +x "$TMPDIR/sbin/md5"
    cat > "$TMPDIR/bin/sudo" <<'SH'
    #!${pkgs.runtimeShell}
    set -eu
    test "$1" = -u && test "$2" = test-user && test "$3" = --
    shift 3
    printf 'user-op %s\n' "$*" >> "$COMMAND_LOG"
    exec "$@"
    SH
    cat > "$TMPDIR/Applications/Docker.app/Contents/MacOS/install" <<'SH'
    #!${pkgs.runtimeShell}
    set -eu
    test "$1" = --accept-license && test "$2" = --user=test-user
    printf 'install %s\n' "$*" >> "$COMMAND_LOG"
    exit "''${INSTALL_STATUS:-0}"
    SH
    chmod +x "$TMPDIR/bin/sudo" "$TMPDIR/Applications/Docker.app/Contents/MacOS/install"
    substitute ${activation} "$TMPDIR/activation" \
      --replace-fail /Users/test-user "$TEST_HOME" \
      --replace-fail /Applications/Docker.app "$TMPDIR/Applications/Docker.app" \
      --replace-fail /usr/local/bin "$TMPDIR/usr/local/bin" \
      --replace-fail /sbin/md5 "$TMPDIR/sbin/md5" \
      --replace-fail /usr/bin/sudo "$TMPDIR/bin/sudo" \
      --replace-fail /usr/bin/readlink '${pkgs.coreutils}/bin/readlink' \
      --replace-fail /bin/ln '${pkgs.coreutils}/bin/ln' \
      --replace-fail /bin/mkdir '${pkgs.coreutils}/bin/mkdir' \
      --replace-fail /usr/bin/touch '${pkgs.coreutils}/bin/touch'
    marker="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
    md5_link="$TMPDIR/usr/local/bin/md5"
    run_activation() { ${pkgs.bash}/bin/bash -e "$TMPDIR/activation"; }

    # A marker from the previous shell installer skips initialization too.
    mkdir -p "$(dirname "$marker")"
    touch "$marker"
    run_activation
    test ! -s "$COMMAND_LOG"
    rm "$marker"

    # A failed initialization must be retried, without marking it complete.
    export INSTALL_STATUS=37
    status=0
    run_activation || status=$?
    test "$status" = 37
    test ! -e "$marker"
    test "$(readlink "$md5_link")" = "$TMPDIR/sbin/md5"
    unset INSTALL_STATUS
    run_activation
    test -f "$marker"
    test "$(grep -c '^install ' "$COMMAND_LOG")" = 2
    test "$(grep -c '^user-op ' "$COMMAND_LOG")" = 2

    # Existing installer markers remain valid; repeat activation is a no-op.
    run_activation
    test "$(grep -c '^install ' "$COMMAND_LOG")" = 2
    test "$(grep -c '^user-op ' "$COMMAND_LOG")" = 2

    # Refuse to replace regular files, different links, and dangling links.
    for conflict in file link dangling; do
      rm "$md5_link"
      case "$conflict" in
        file) printf 'keep\n' > "$md5_link" ;;
        link) ln -s "$TMPDIR/sbin/md5" "$TMPDIR/other-md5"; ln -s "$TMPDIR/other-md5" "$md5_link" ;;
        dangling) ln -s "$TMPDIR/missing-md5" "$md5_link" ;;
      esac
      status=0
      run_activation > "$TMPDIR/error" 2>&1 || status=$?
      test "$status" != 0
      grep -q 'md5 compatibility path conflicts' "$TMPDIR/error"
      case "$conflict" in
        file) test "$(cat "$md5_link")" = keep ;;
        link) test "$(readlink "$md5_link")" = "$TMPDIR/other-md5" ;;
        dangling) test "$(readlink "$md5_link")" = "$TMPDIR/missing-md5" ;;
      esac
    done
    test "$(grep -c '^install ' "$COMMAND_LOG")" = 2

    rm "$md5_link"
    chmod -x "$TMPDIR/sbin/md5"
    status=0
    run_activation > "$TMPDIR/error" 2>&1 || status=$?
    test "$status" != 0
    grep -q 'macOS md5 executable is unavailable' "$TMPDIR/error"
    test ! -e "$md5_link"

    echo 'Docker Desktop initialization, retry, idempotence, and conflict checks passed'
    touch "$out"
  ''
