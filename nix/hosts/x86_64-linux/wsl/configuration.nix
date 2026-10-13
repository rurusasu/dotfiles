# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{
  config,
  lib,
  pkgs,
  ...
}:

let
  identity = import ../../shared/nixos/identity.nix { inherit lib; };
  inherit (identity) user stateVersion;
  graphicsEnvironment = {
    # Mesa dynamically loads the Windows bridge libraries from this directory.
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    # https://github.com/microsoft/wslg/issues/1332
    GALLIUM_DRIVER = "d3d12";
  };
  # WSLg exports these to shells, but the user manager starts without a
  # desktop login and needs them for D-Bus-activated GTK portal backends.
  wslgServiceEnvironment = graphicsEnvironment // {
    DISPLAY = ":0";
    WAYLAND_DISPLAY = "wayland-0";
  };
in

{
  imports = [
    # include NixOS-WSL modules
  ];

  wsl = {
    enable = true;
    defaultUser = user;
    # Expose Windows D3D12/DXCore libraries through /run/opengl-driver/lib.
    useWindowsDriver = true;
  };

  # Cover both login shells and GUI apps activated by the user systemd manager.
  environment.variables = graphicsEnvironment;
  environment.etc."environment.d/60-wsl-graphics.conf".text =
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name}=${value}") wslgServiceEnvironment
    )
    + "\n";

  # WSLg has no desktop session manager to activate this target. Recent
  # xdg-desktop-portal units require it even when activated through D-Bus.
  systemd.user.targets.graphical-session.wantedBy = [ "default.target" ];

  # XDG desktop portal: provides color-scheme and other settings queries via D-Bus.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  # Windows bootstrap records explicit choices in /etc/nixos/dotfiles.json.
  # Existing systems retain the persisted version, or the original 25.05 default.
  system.stateVersion = stateVersion;
  assertions = [
    {
      assertion = builtins.match "[0-9]{2}\\.[0-9]{2}" stateVersion != null;
      message = "The NixOS stateVersion must use YY.MM format.";
    }
  ];
  system.activationScripts.dotfilesHostState.text = ''
    install -d -m 0755 /var/lib/dotfiles
    printf '%s\n' ${lib.escapeShellArg user} > /var/lib/dotfiles/user
    printf '%s\n' ${lib.escapeShellArg config.system.stateVersion} > /var/lib/dotfiles/system-state-version
  '';
}
