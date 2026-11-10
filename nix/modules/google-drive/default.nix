# Drive's signed PKG installs root-owned helpers as well as the application.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.google-drive;
in
{
  options.programs.google-drive = {
    enable = lib.mkEnableOption "Google Drive for desktop";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix { inherit inputs pkgs; };
      description = "Nix-managed official Google Drive installer.";
    };
  };
  config = lib.mkMerge [
    { programs.google-drive.enable = true; }
    (lib.mkIf cfg.enable {
      system.activationScripts.postActivation.text = lib.mkAfter ''
        if [ ! -d "/Applications/Google Drive.app" ] || \
           [ "$(/bin/cat /var/lib/dotfiles/google-drive-source 2>/dev/null || true)" != "${cfg.package}" ]; then
          if (
            googleDriveMount="$(/usr/bin/mktemp -d /private/tmp/dotfiles-google-drive.XXXXXX)" || exit 1
            trap '/usr/bin/hdiutil detach "$googleDriveMount" -quiet || exit 1; /bin/rmdir "$googleDriveMount" 2>/dev/null || true' EXIT
            /usr/bin/hdiutil attach -quiet -readonly -nobrowse \
              -mountpoint "$googleDriveMount" "${cfg.package}/GoogleDrive.dmg" || exit 1
            /usr/sbin/installer -pkg "$googleDriveMount/GoogleDrive.pkg" -target /
          ); then
          /bin/mkdir -p /var/lib/dotfiles
          printf '%s' '${cfg.package}' > /var/lib/dotfiles/google-drive-source.new
          /bin/mv /var/lib/dotfiles/google-drive-source.new /var/lib/dotfiles/google-drive-source
          else
            exit 1
          fi
        fi
      '';
    })
  ];
}
