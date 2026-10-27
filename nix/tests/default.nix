{ inputs, ... }:
let
  context = import ./context.nix { inherit inputs; };
in
{
  perSystem =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [
        {
          options.nix-unit.inputs = lib.mkOption {
            # Preserve regular-file inputs and source revisions in the sandbox.
            apply = lib.mapAttrs (
              _: input: "path:${input}${lib.optionalString (input ? rev) "?rev=${input.rev}"}"
            );
          };
        }
      ];
      checks =
        (import ./discover.nix {
          directory = ./build;
          suffix = ".check.nix";
          allowEmptyFiles = true;
          args = context // {
            inherit
              inputs
              pkgs
              lib
              config
              ;
          };
        }).values;
      nix-unit.inputs = {
        # Full Darwin activation evaluation needs this nested input in the sandbox.
        "nix-homebrew/brew-src" = inputs.nix-homebrew.inputs.brew-src;
        # Hermes activation also evaluates its locked package input closure.
        "hermes-agent/nixpkgs" = inputs.hermes-agent.inputs.nixpkgs;
        "hermes-agent/flake-parts" = inputs.hermes-agent.inputs.flake-parts;
        "hermes-agent/home-manager" = inputs.hermes-agent.inputs.home-manager;
        "hermes-agent/pyproject-nix" = inputs.hermes-agent.inputs.pyproject-nix;
        "hermes-agent/uv2nix" = inputs.hermes-agent.inputs.uv2nix;
        "hermes-agent/pyproject-build-systems" = inputs.hermes-agent.inputs.pyproject-build-systems;
        "hermes-agent/npm-lockfile-fix" = inputs.hermes-agent.inputs.npm-lockfile-fix;
        # Preserve llm-agents' own dependency graph inside the test sandbox.
        "llm-agents/nixpkgs" = inputs.llm-agents.inputs.nixpkgs;
        "llm-agents/bun2nix" = inputs.llm-agents.inputs.bun2nix;
        "llm-agents/flake-parts" = inputs.llm-agents.inputs.flake-parts;
        "llm-agents/systems" = inputs.llm-agents.inputs.systems;
        "llm-agents/treefmt-nix" = inputs.llm-agents.inputs.treefmt-nix;
        "mcp-servers/nixpkgs" = inputs.mcp-servers.inputs.nixpkgs;
        inherit (inputs)
          devcontainer-cli-nvim
          dia
          flake-parts
          home-manager
          hermes-agent
          hermes-lcm
          llm-agents
          mcp-servers
          modes-nvim
          nix-darwin
          nix-homebrew
          nix-unit
          nixos-vscode-server
          nixos-wsl
          nixpkgs
          psscriptanalyzer
          strata-release
          systems
          treefmt-nix
          xurl
          ;
      };

      nix-unit.tests =
        (import ./discover.nix {
          directory = ./unit;
          args = context;
        }).values;
    };
}
