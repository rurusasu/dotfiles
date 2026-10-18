# Linux GUI installation. Hosts select the native or WSLg package set.
let
  linuxDesktopWith =
    chromeProvider:
    { lib, pkgs, ... }:
    {
      imports = [ ./fonts/gtk.nix ];
      home.packages =
        lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          (chromeProvider pkgs)
          pkgs.obsidian
          pkgs._1password-gui
          pkgs.nautilus
        ]
        # Upstream currently publishes the Linux Desktop binary only for x86_64.
        ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
          (pkgs.callPackage ./comfyui/package.nix { })
        ];
    };
in
{
  linuxDesktop = linuxDesktopWith (pkgs: pkgs.google-chrome);

  wslDesktop =
    { lib, pkgs, ... }:
    {
      imports = [ (linuxDesktopWith (pkgs: import ./browsers/chrome { inherit pkgs; })) ];
      # The WSL host is x86_64; Spotify's Linux binary is not available for ARM.
      home.packages = lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
        pkgs.spotify
        pkgs.signal-desktop
      ];
    };
}
