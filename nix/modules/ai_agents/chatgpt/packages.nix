# Native desktop and the CLI shipped in the same official distribution.
{ inputs, pkgs }:
let
  desktopPkgs = import inputs.chatgpt-nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  # Upstream otherwise replaces these binaries with its separate Codex package.
  chatgpt = desktopPkgs.chatgpt.override { codex = null; };
  node = desktopPkgs.lib.getExe desktopPkgs.nodejs-slim;
  resources =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${chatgpt}/Applications/ChatGPT.app/Contents/Resources"
    else
      "${chatgpt}/lib/chatgpt/resources";
  codex = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [
      desktopPkgs.nodejs-slim
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ desktopPkgs.bubblewrap ];
    # The package version tracks the distribution containing this CLI.
    derivationArgs.version = chatgpt.version;
    passthru = { inherit chatgpt resources; };
    text = ''
      export NODE_REPL_NODE_PATH="''${NODE_REPL_NODE_PATH:-${node}}"
      export CODEX_BROWSER_USE_NODE_PATH="''${CODEX_BROWSER_USE_NODE_PATH:-${node}}"
      # Keep codex-code-mode-host beside the original executable.
      exec ${resources}/codex "$@"
    '';
  };
in
assert pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin;
{
  inherit chatgpt codex resources;
}
