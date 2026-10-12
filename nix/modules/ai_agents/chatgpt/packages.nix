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
      "${chatgpt}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin"
    else
      "${chatgpt}/lib/chatgpt/resources";
  codex = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [
      desktopPkgs.nodejs-slim
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ desktopPkgs.bubblewrap ];
    # Home Manager gates config features using the CLI version, not app version.
    # Both pinned distributions bundle this version; the build check enforces it.
    derivationArgs.version = "0.162.0-alpha.17.2";
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
