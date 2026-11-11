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
    # Share the cross-platform rolling channel between Linux and Darwin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Follow upstream; flake.lock records the selected source and build toolchain.
    herdr.url = "github:herdrdev/herdr";
    omarchy = {
      url = "github:omacom/omarchy/quattro";
      flake = false;
    };
    # Use the upstream package set unchanged so its binary cache can be used.
    llm-agents.url = "github:numtide/llm-agents.nix";
    mcp-servers.url = "github:natsukium/mcp-servers-nix";
    docker-mcp = {
      url = "github:docker/mcp-gateway";
      flake = false;
    };
    # Strata is not in nixpkgs. Pin the complete release asset list, including per-OS hotfixes.
    strata-release = {
      type = "file";
      url = "https://github.com/Niko1221/Strata/releases/latest/download/SHA256SUMS.txt";
      flake = false;
    };
    xurl = {
      url = "github:xdevplatform/xurl";
      flake = false;
    };
    dia = {
      type = "file";
      url = "https://releases.diabrowser.com/release/Dia-latest.dmg";
      flake = false;
    };
    steam-darwin = {
      type = "file";
      url = "https://cdn.akamai.steamstatic.com/client/installer/steam.dmg";
      flake = false;
    };
    google-drive = {
      type = "file";
      url = "https://dl.google.com/drive-file-stream/GoogleDrive.dmg";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    modes-nvim = {
      url = "github:mvllow/modes.nvim";
      flake = false;
    };
    hermes-lcm = {
      url = "github:stephenschoettler/hermes-lcm";
      flake = false;
    };
    hermes-agent = {
      # Keep the upstream package and its complete locked dependency graph intact.
      # Following this repository's nixpkgs changes derivations and cache identities.
      url = "github:NousResearch/hermes-agent";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    let
      stateVersions = {
        home = "26.05";
        darwin = 6;
        nixos = "26.05";
      };
      defaults = import ./nix/defaults.nix inputs;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.nix-unit.modules.flake.default
        inputs.treefmt-nix.flakeModule
        ./nix/modules/formatters
        ./nix/tests
      ];

      # Current nixpkgs supports Apple Silicon macOS, not x86_64-darwin.
      systems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);

      inherit (defaults) perSystem;

      flake = defaults.configurations // {
        lib = { inherit stateVersions; };
      };
    };
}
