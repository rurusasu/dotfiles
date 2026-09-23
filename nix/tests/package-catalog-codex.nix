{ inputs }:
let
  system = "aarch64-darwin";
  pkgs =
    (import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    }).extend
      (_: _: {
        workmux = inputs.workmux.packages.${system}.default;
      });
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = inputs.llm-agents.packages.${system}.codex;
  };
  support = sets.supportReport.codex;
in
{
  testCodexSupportMetadataRecordsExternalProvider = {
    expr = {
      providerErrors = sets.providerErrors;
      support = {
        windows = {
          inherit (support.windows) provider source identity;
        };
        darwin = {
          inherit (support.darwin) provider source identity;
        };
        linux = {
          inherit (support.linux) provider source identity;
        };
      };
    };
    expected = {
      providerErrors = [ ];
      support = {
        windows = {
          provider = "winget";
          source = "winget";
          identity = "OpenAI.Codex";
        };
        darwin = {
          provider = "nix";
          source = "llm-agents.nix";
          identity = {
            command = "codex";
            versionArgs = [ "--version" ];
          };
        };
        linux = {
          provider = "nix";
          source = "llm-agents.nix";
          identity = {
            command = "codex";
            versionArgs = [ "--version" ];
          };
        };
      };
    };
  };
}
