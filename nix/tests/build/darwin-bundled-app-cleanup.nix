{ pkgs }:
let
  cleanup = import ../../hosts/darwin-app-cleanup.nix { inherit pkgs; };
in
pkgs.runCommand "darwin-bundled-app-cleanup-check" { } ''
  fixture="$TMPDIR/mac with spaces"
  applications="$fixture/Applications"
  mkdir -p "$applications"

  make_app() {
    mkdir -p "$1/Contents"
    cat > "$1/Contents/Info.plist" <<EOF
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>$2</string>
  </dict></plist>
  EOF
    touch "$1/Contents/keep-until-cleanup"
  }

  expect_rejection() {
    if ${pkgs.lib.getExe cleanup} "$applications" > "$TMPDIR/rejection.log" 2>&1; then
      echo 'Unsafe app cleanup unexpectedly succeeded' >&2
      exit 1
    fi
    grep -F "$1" "$TMPDIR/rejection.log"
    # A later invalid selection must prevent deletion of earlier valid apps.
    test -f "$applications/GarageBand.app/Contents/keep-until-cleanup"
  }

  # Keep other applications, protected-system lookalikes, and adjacent user data.
  make_app "$applications/Safari.app" com.apple.Safari
  make_app "$applications/GarageBand.app.backup" com.apple.garageband10
  make_app "$fixture/System/Applications/GarageBand.app" com.apple.garageband10
  mkdir -p "$fixture/Library/Application Support/GarageBand" "$fixture/Documents"
  touch "$fixture/Library/Application Support/GarageBand/instruments" "$fixture/Documents/song.band"

  # Both existing and current iWork identifiers are recognized by the real executable.
  for iwork_prefix in com.apple.iWork com.apple; do
    make_app "$applications/GarageBand.app" com.apple.garageband10
    make_app "$applications/iMovie.app" com.apple.iMovieApp
    make_app "$applications/Pages.app" "$iwork_prefix.Pages"
    make_app "$applications/Numbers.app" "$iwork_prefix.Numbers"
    make_app "$applications/Keynote.app" "$iwork_prefix.Keynote"
    ${pkgs.lib.getExe cleanup} "$applications"
    for app in GarageBand iMovie Pages Numbers Keynote; do
      test ! -e "$applications/$app.app"
    done
    ${pkgs.lib.getExe cleanup} "$applications"
    test -f "$applications/Safari.app/Contents/keep-until-cleanup"
    test -f "$applications/GarageBand.app.backup/Contents/keep-until-cleanup"
    test -f "$fixture/System/Applications/GarageBand.app/Contents/keep-until-cleanup"
    test -f "$fixture/Library/Application Support/GarageBand/instruments"
    test -f "$fixture/Documents/song.band"
  done

  make_app "$applications/GarageBand.app" com.apple.garageband10
  make_app "$applications/Numbers.app" org.example.Numbers
  expect_rejection 'unexpected bundle identifier'
  test -f "$applications/Numbers.app/Contents/keep-until-cleanup"
  rm -rf -- "$applications/Numbers.app"

  # A selected symlink must never lead cleanup outside the Applications directory.
  make_app "$TMPDIR/outside/Numbers.app" com.apple.Numbers
  ln -s "$TMPDIR/outside/Numbers.app" "$applications/Numbers.app"
  expect_rejection 'symlink'
  test -L "$applications/Numbers.app"
  test -f "$TMPDIR/outside/Numbers.app/Contents/keep-until-cleanup"
  rm -- "$applications/Numbers.app"
  ln -s "$TMPDIR/absent.app" "$applications/Numbers.app"
  expect_rejection 'symlink'
  test -L "$applications/Numbers.app"
  rm -- "$applications/Numbers.app"

  touch "$applications/Numbers.app"
  expect_rejection 'not a directory'
  test -f "$applications/Numbers.app"
  rm -- "$applications/Numbers.app"
  mkdir -p "$applications/Numbers.app/Contents"
  expect_rejection 'Info.plist'
  printf 'invalid plist\n' > "$applications/Numbers.app/Contents/Info.plist"
  expect_rejection 'CFBundleIdentifier'

  echo 'Apple app cleanup identity, preservation, prevalidation, and idempotence checks passed'
  touch "$out"
''
