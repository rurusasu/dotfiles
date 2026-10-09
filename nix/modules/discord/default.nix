{
  config,
  lib,
  pkgs,
  ...
}:
let
  bundledModulesPath = "Applications/Discord.app/Contents/Resources/modules";
  modulesPath = "share/discord/modules";
in
{
  programs.discord = {
    enable = true;
    settings.SKIP_HOST_UPDATE = true;
    package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      pkgs.discord.overrideAttrs (old: {
        # Keep the official application signature intact, including its resources.
        dontFixup = true;
        postInstall = (old.postInstall or "") + ''
          mkdir -p "$out/share/discord"
          mv "$out/${bundledModulesPath}" "$out/${modulesPath}"
          substituteInPlace "$out/bin/Discord" \
            --replace-fail "$out/${bundledModulesPath}" "$out/${modulesPath}"
        '';
      })
    );
  };

  # Launching the app bundle directly does not run nixpkgs' CLI wrapper.
  launchd.agents.discord-module-staging = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.programs.discord.package.passthru.stageModules}"
        "${config.programs.discord.package}/${modulesPath}"
      ];
      RunAtLoad = true;
      KeepAlive.PathState = {
        "${config.home.homeDirectory}/Library/Application Support/discord/${config.programs.discord.package.version}/modules/installed.json" =
          false;
      };
    };
  };
}
