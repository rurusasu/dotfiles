{
  pkgs,
  chatgpt ? pkgs.chatgpt.override { codex = null; },
}:
let
  # Upstream otherwise replaces these binaries with its separate Codex package.
  resources =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${chatgpt}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin"
    else
      "${chatgpt}/lib/chatgpt/resources";
in
assert pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin;
{
  inherit chatgpt;
  codex = pkgs.linkFarm "codex" (
    {
      "bin/codex" = "${resources}/codex";
      "bin/codex-code-mode-host" = "${resources}/codex-code-mode-host";
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      "bin/bwrap" = pkgs.lib.getExe pkgs.bubblewrap;
    }
  );
}
