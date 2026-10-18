{ inputs }:
let
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  mkSettings =
    system: extraConfig:
    (fixtures.mkHome system [
      ../../../modules/shells/plugins/starship
      { programs.starship.enable = true; }
      extraConfig
    ]).config.programs.starship.settings;
  nixos = mkSettings "x86_64-linux" { dotfiles.starship.osSymbol = "❄️ "; };
  darwin = mkSettings "aarch64-darwin" { dotfiles.starship.osSymbol = "🍎 "; };
  fallback = mkSettings "x86_64-linux" { };
in
{
  testStarshipStaticNixOSSymbolReplacesRuntimeOsModule = {
    expr = {
      inherit (nixos) format;
      osDisabled = nixos.os.disabled;
    };
    expected = {
      format = "[❄️ ](bold white) $username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = true;
    };
  };

  testStarshipStaticDarwinSymbolReplacesRuntimeOsModule = {
    expr = {
      inherit (darwin) format;
      osDisabled = darwin.os.disabled;
    };
    expected = {
      format = "[🍎 ](bold white) $username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = true;
    };
  };

  testStarshipUnknownOsKeepsRuntimeDetection = {
    expr = {
      inherit (fallback) format;
      osDisabled = fallback.os.disabled;
      osFormat = fallback.os.format;
    };
    expected = {
      format = "$os$username$hostname$memory_usage$directory$git_branch$git_status$nix_shell$character";
      osDisabled = false;
      osFormat = "[$symbol]($style) ";
    };
  };
}
