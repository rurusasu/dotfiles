{
  pkgs,
  fixtures,
  code,
}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
  google-drive-installation =
    let
      installer = pkgs.writeTextDir "GoogleDrive.dmg" "installer fixture";
      host = fixtures.mkDarwin [
        code.nix.modules.google-drive.default
        { programs.google-drive.package = installer; }
      ];
      activation =
        builtins.replaceStrings
          [
            "/usr/bin/hdiutil"
            "/usr/sbin/installer"
            "/var/lib/dotfiles"
            "/Applications/Google Drive.app"
            "/private/tmp/dotfiles-google-drive.XXXXXX"
          ]
          [ "hdiutil" "installer" "$TMPDIR/state" "$TMPDIR/Google Drive.app" "$TMPDIR/mount.XXXXXX" ]
          host.config.system.activationScripts.postActivation.text;
    in
    pkgs.runCommand "google-drive-installation-check" { nativeBuildInputs = [ pkgs.bash ]; } ''
      mkdir -p "$TMPDIR/bin" "$TMPDIR/Google Drive.app"
      export PATH="$TMPDIR/bin:$PATH"
      export TRACE="$TMPDIR/trace"
      cat > "$TMPDIR/bin/hdiutil" <<'SH'
      #!/bin/bash
      set -eu
      echo "$1" >> "$TRACE"
      SH
      cat > "$TMPDIR/bin/installer" <<'SH'
      #!/bin/bash
      echo install >> "$TRACE"
      exit "''${INSTALL_STATUS:-0}"
      SH
      chmod +x "$TMPDIR/bin/"*
      cat > "$TMPDIR/activate" <<'SH'
      ${activation}
      SH

      bash "$TMPDIR/activate"
      test "$(cat "$TMPDIR/state/google-drive-source")" = '${installer}'
      bash "$TMPDIR/activate"
      test "$(grep -c '^install$' "$TRACE")" -eq 1

      rm "$TMPDIR/state/google-drive-source"
      export INSTALL_STATUS=23
      if bash "$TMPDIR/activate"; then
        echo 'Installer failure was ignored' >&2
        exit 1
      fi
      test ! -e "$TMPDIR/state/google-drive-source"
      test "$(grep -c '^detach$' "$TRACE")" -eq 2
      touch "$out"
    '';
}
