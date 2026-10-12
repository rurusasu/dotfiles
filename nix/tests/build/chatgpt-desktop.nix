{ inputs, pkgs }:
let
  packages = import ../../modules/ai_agents/chatgpt/packages.nix { inherit inputs pkgs; };
in
pkgs.runCommand "chatgpt-desktop-check" { nativeBuildInputs = [ packages.codex ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  test -x ${pkgs.lib.getExe packages.chatgpt}
  test -x ${packages.resources}/codex-code-mode-host
  ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
    test -f ${packages.chatgpt}/share/applications/chatgpt.desktop
    cmp ${packages.chatgpt}/share/user-tmpfiles.d/chatgpt.conf \
      ${inputs.chatgpt-nixpkgs}/pkgs/by-name/ch/chatgpt/tmpfiles.conf
  ''}
  codex --version
  touch "$out"
''
