{
  accept-flake-config = false;
  experimental-features = [
    "nix-command"
    "flakes"
  ];
  extra-substituters = [
    "https://cache.numtide.com"
    "https://hermes-agent.cachix.org"
  ];
  extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
  ];
}
