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
          home.config.home.packages
          ++ [ pkgs.jq ]
          ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.rsync;
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

        export CODEX_HOME="$HOME/.config/codex"
        mkdir -p "$CODEX_HOME"
        cat > "$CODEX_HOME/config.toml" <<'TOML'
        [features]
        plugins = true

        [marketplaces.home-manager]
        source_type = "local"
        source = "${home.config.programs.codex.marketplaces.home-manager}"
        TOML
        codex plugin add pstack@home-manager --json > "$TMPDIR/pstack-install.json"
        installed="$(jq -er 'select(.pluginId == "pstack@home-manager") | .installedPath' "$TMPDIR/pstack-install.json")"
        test -d "$installed"
        test ! -L "$installed"
        touch "$out"
      '';
}
