{ pkgs }:
pkgs.runCommand "ghostty-config-check"
  {
    nativeBuildInputs = [
      pkgs.bats
      pkgs.chezmoi
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export GHOSTTY_TEST_REPO_ROOT=${../../..}
    mkdir -p "$HOME"
    bats ${../../../tests/bash/ghostty_config.bats}
    touch "$out"
  ''
