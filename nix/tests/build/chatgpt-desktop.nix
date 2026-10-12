{ inputs, pkgs }:
let
  packages = import ../../modules/ai_agents/chatgpt/packages.nix { inherit inputs pkgs; };
in
pkgs.runCommand "chatgpt-desktop-check" { nativeBuildInputs = [ packages.codex ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  test -x ${packages.chatgpt}/bin/chatgpt
  test -x ${packages.chatgpt}/lib/chatgpt/resources/codex-code-mode-host
  test -f ${packages.chatgpt}/share/applications/chatgpt.desktop
  test -f ${packages.chatgpt}/share/user-tmpfiles.d/chatgpt.conf
  codex --version
  touch "$out"
''
