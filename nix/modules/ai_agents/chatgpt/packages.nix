# Native Linux desktop and the CLI shipped in the same official distribution.
{ inputs, pkgs }:
let
  desktopPkgs = import inputs.chatgpt-nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  # Upstream otherwise replaces these binaries with its separate Codex package.
  chatgpt = desktopPkgs.chatgpt.override { codex = null; };
  node = desktopPkgs.lib.getExe desktopPkgs.nodejs-slim;
  codex = pkgs.runCommand "codex" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p "$out/bin"
    # Execute in the original resource directory: codex-code-mode-host must stay
    # beside the CLI, and both binaries must come from the same app version.
    makeWrapper ${chatgpt}/lib/chatgpt/resources/codex "$out/bin/codex" \
      --prefix PATH : ${
        desktopPkgs.lib.makeBinPath [
          desktopPkgs.bubblewrap
          desktopPkgs.nodejs-slim
        ]
      } \
      --set-default NODE_REPL_NODE_PATH ${node} \
      --set-default CODEX_BROWSER_USE_NODE_PATH ${node}
  '';
in
assert pkgs.stdenv.hostPlatform.isLinux;
{
  inherit chatgpt codex;
}
