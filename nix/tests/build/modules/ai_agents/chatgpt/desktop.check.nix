{
  pkgs,
  fixtures,
}:
{
  chatgpt-desktop =
    let
      outerPkgs = pkgs;
    in
    let
      pkgs = fixtures.mkPkgs outerPkgs.stdenv.hostPlatform.system;

      home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [ { programs.chatgpt.enable = true; } ];
      chatgpt = home.config.programs.chatgpt.package;
    in
    pkgs.runCommand "chatgpt-desktop-check"
      {
        nativeBuildInputs =
          home.config.home.packages ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.rsync;
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        test -x ${pkgs.lib.getExe chatgpt}
        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          test -x ${chatgpt}/lib/chatgpt/resources/codex-code-mode-host
          test -f ${chatgpt}/share/applications/chatgpt.desktop
        ''}
        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          test -x ${chatgpt}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex-code-mode-host
          # codesign rejects Nix's epoch timestamps; copy without preserving times.
          rsync --recursive --perms --links --copy-unsafe-links --specials --chmod=+w \
            ${chatgpt}/Applications/ChatGPT.app/ "$TMPDIR/ChatGPT.app/"
          app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$TMPDIR/ChatGPT.app/Contents/Info.plist")"
          test "$app_version" = "${chatgpt.version}"
          /usr/bin/codesign --verify --deep --strict \
            --test-requirement='=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2"' \
            "$TMPDIR/ChatGPT.app"
        ''}
        ${home.config.home.sessionVariables.CODEX_MCP_NODE_PATH} --version
        version="$(codex --version)"
        echo "$version"
        [[ "$version" == "codex-cli "* ]]
        [[ "$(realpath "$(command -v codex)")" == ${chatgpt}/* ]]
        touch "$out"
      '';
}
