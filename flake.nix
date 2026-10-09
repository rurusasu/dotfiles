{
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://hermes-agent.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.flake-parts.follows = "flake-parts";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Use the upstream package set unchanged so its binary cache can be used.
    llm-agents.url = "github:numtide/llm-agents.nix";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      # Keep the upstream package and its complete locked dependency graph intact.
      # Following this repository's nixpkgs changes derivations and cache identities.
      url = "github:NousResearch/hermes-agent/d337b736aa1e8ebecfab043842d13e4a2d2f48a3";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    let
      hosts = import ./nix/hosts { inherit inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.nix-unit.modules.flake.default
        inputs.treefmt-nix.flakeModule
        ./nix/packages/outputs.nix
        ./nix/tests
        ./nix/formatter.nix
      ];

      # Current nixpkgs supports Apple Silicon macOS, not x86_64-darwin.
      systems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);

      perSystem = hosts.mkApps;

      flake = import ./nix/hosts/configurations.nix { inherit inputs; };
    };
}
