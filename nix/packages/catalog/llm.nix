# Package identities and provider declarations for llm.
{ pkgs, ... }:
{
  codex = {
    # Codex CLI is intentionally kept out of Nix package outputs. The
    # npm package is the single CLI provider on every supported OS so
    # `codex update` can identify and update its installation method.
    pkg = null;
    npm = "@openai/codex";
    category = "llm";
    support = {
      windows = {
        provider = "npm";
        source = "npm";
        identity = "@openai/codex";
      };
      darwin = {
        provider = "npm";
        source = "npm";
        identity = "@openai/codex";
      };
      linux = {
        provider = "npm";
        source = "npm";
        identity = "@openai/codex";
      };
    };
  };

  ollama = {
    pkg = pkgs.ollama;
    winget = "Ollama.Ollama";
    category = "llm";
    installFeature = "WithOllama";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "ollama";
        identity = "ollama";
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "ollama";
        nixAttr = "ollama";
      };
    };
  };

  workmux = {
    pkg = pkgs.workmux;
    winget = null;
    category = "llm";
  };
}
