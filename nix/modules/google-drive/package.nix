# Preserve the vendor DMG intact; its APFS image is mounted only during activation.
{ inputs, pkgs }:
pkgs.runCommand "google-drive-installer"
  {
    meta = {
      description = "Official Google Drive signed macOS installer";
      homepage = "https://www.google.com/drive/download/";
      license = pkgs.lib.licenses.unfree;
      platforms = [ "aarch64-darwin" ];
    };
  }
  ''
    mkdir -p "$out"
    ln -s ${inputs.google-drive} "$out/GoogleDrive.dmg"
  ''
