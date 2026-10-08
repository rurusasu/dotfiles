{ inputs, ... }:
{
  imports = [
    ../../../modules/fonts.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
    # Keep only the current generation of each profile.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-old";
    };
  };
  nixpkgs.config.allowUnfree = true;
  # Home Manager connects SSH clients to the 1Password desktop agent.
  programs = {
    ssh.startAgent = false;
    gnupg.agent.enableSSHSupport = false;
    zsh = {
      enable = true;
      # Home Manager の zsh-autocomplete に補完初期化を任せる。
      enableGlobalCompInit = false;
    };
  };
  fonts.fontDir.enable = true;

  # WSL の per-user profile にも言語サーバーを公開する。
  home-manager.sharedModules = [
    ../../../modules/shells/zsh
    ../linux-ghostty.nix
    ../../../modules/terminals/ghostty/defaults.nix
    ../../../modules/terminals/wezterm/defaults.nix
    ../../../modules/lsp.nix
  ];
}
