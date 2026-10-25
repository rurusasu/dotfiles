# Chrome installation and WSL-specific locale/input-method integration.
let
  package =
    { pkgs }:
    let
      # The WSL host runs its own fcitx5 service without NixOS inputMethod's cache.
      # GTK3 needs this registration file to discover the installed fcitx plugin.
      gtk3ImmodulesCache =
        pkgs.runCommand "chrome-fcitx-gtk3-immodules.cache"
          {
            nativeBuildInputs = [
              pkgs.gtk3
              pkgs.pkg-config
            ];
            preferLocalBuild = true;
            allowSubstitutes = false;
            disallowedReferences = [ (pkgs.lib.getDev pkgs.gtk3) ];
          }
          ''
            gtk_binary_version="$(pkg-config --variable=gtk_binary_version gtk+-3.0)"
            gtk-query-immodules-3.0 "${pkgs.fcitx5-gtk}/lib/gtk-3.0/$gtk_binary_version/immodules/im-fcitx5.so" > "$out"
          '';
    in
    pkgs.google-chrome.overrideAttrs (previous: {
      passthru = (previous.passthru or { }) // {
        inherit gtk3ImmodulesCache;
      };
      postFixup = (previous.postFixup or "") + ''
        wrapProgram "$out/bin/google-chrome-stable" \
          --set LANG ja_JP.UTF-8 \
          --set LC_ALL ja_JP.UTF-8 \
          --set LANGUAGE ja \
          --set GTK_IM_MODULE_FILE "${gtk3ImmodulesCache}" \
          --add-flags --lang=ja
      '';
    });

  homeManager = { lib, pkgs, ... }: {
    programs.chromium = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      package = lib.mkDefault pkgs.google-chrome;
    };
  };
in
{
  inherit package homeManager;

  wsl =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ homeManager ];
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.chromium.package = package { inherit pkgs; };
        home.sessionVariables.BROWSER = lib.getExe config.programs.chromium.finalPackage;
      };
    };
}
