{
  pkgs,
  lib,
  inputs,
  installFeatures ? [ ],
  ...
}:
let
  codexPackage = inputs."llm-agents".packages.${pkgs.stdenv.hostPlatform.system}.codex;
  managedFontPackage = pkgs.udev-gothic-nf;
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
    inherit codexPackage;
  };
in
{
  imports = [
    ./common.nix
    ./hermes-agent.nix
  ];

  # macOS installs the WezTerm GUI through Homebrew, so add its Nix terminfo
  # output separately for shells and tools that resolve TERM=wezterm.
  home.packages = lib.unique (
    sets.darwinHomePackagesForInstallFeatures installFeatures
    ++ [
      managedFontPackage
      pkgs.coreutils
      pkgs.wezterm.terminfo
    ]
  );

  # Nix installs the font into the profile, but macOS GUI applications discover
  # user fonts through ~/Library/Fonts. Keep the package declarative while
  # registering its font files for native macOS applications as well.
  home.activation.installDotfilesFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontTarget="$HOME/Library/Fonts"
    fontSource="${managedFontPackage}/share/fonts"

    run mkdir -p "$fontTarget"
    if [ -d "$fontSource" ]; then
      ${pkgs.findutils}/bin/find "$fontSource" -type f \( -name '*.ttf' -o -name '*.otf' \) -print |
        while IFS= read -r fontPath; do
          fontName="$(basename "$fontPath")"
          run cp -f "$fontPath" "$fontTarget/$fontName"
        done
    fi
  '';

  home.sessionVariables = {
    # Homebrew's default is already 24 hours; keep that interval explicit
    # for interactive shells and tools launched from the Home Manager session.
    HOMEBREW_AUTO_UPDATE_SECS = "86400";
    # Let native op use the unlocked 1Password desktop app integration.
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };

  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  # A long-lived GUI process can inherit Home Manager's session sentinel
  # without retaining the variables that were set alongside it. Restore
  # WezTerm's Darwin terminfo path in .zshenv so interactive shells can
  # initialize zsh/terminfo even in that state.
  programs.zsh.envExtra = ''
    if [[ "''${TERM-}" == wezterm && -d "/etc/profiles/per-user/''${USER}/share/terminfo" ]]; then
      export TERMINFO_DIRS="/etc/profiles/per-user/''${USER}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}:/usr/share/terminfo"
    fi
  '';

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
