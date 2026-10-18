{ inputs, pkgs }:
let
  packages = import ../../modules/ai_agents/chatgpt/packages.nix { inherit inputs pkgs; };
in
pkgs.runCommand "chatgpt-desktop-check"
  {
    nativeBuildInputs = [
      packages.codex
    ]
    ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.rsync;
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    test -x ${pkgs.lib.getExe packages.chatgpt}
    test -x ${packages.resources}/codex-code-mode-host
    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      test -f ${packages.chatgpt}/share/applications/chatgpt.desktop
      cmp ${packages.chatgpt}/share/user-tmpfiles.d/chatgpt.conf \
        ${inputs.chatgpt-nixpkgs}/pkgs/by-name/ch/chatgpt/tmpfiles.conf
    ''}
    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      # codesign rejects Nix's epoch timestamps; copy without preserving times.
      rsync --recursive --perms --links --copy-unsafe-links --specials --chmod=+w \
        ${packages.chatgpt}/Applications/ChatGPT.app/ "$TMPDIR/ChatGPT.app/"
      app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$TMPDIR/ChatGPT.app/Contents/Info.plist")"
      test "$app_version" = "${packages.chatgpt.version}"
      /usr/bin/codesign --verify --deep --strict \
        --test-requirement='=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2"' \
        "$TMPDIR/ChatGPT.app"
    ''}
    version="$(codex --version)"
    echo "$version"
    test "$version" = "codex-cli ${packages.codex.version}"
    touch "$out"
  ''
