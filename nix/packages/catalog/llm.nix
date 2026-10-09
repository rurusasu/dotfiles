# Package identities and provider declarations for llm.
_: {
  codex = {
    # Codex CLI is intentionally kept out of Nix package outputs. The
    # npm package is the CLI provider on Unix so
    # `codex update` can identify and update its installation method.
    pkg = null;
    npm = "@openai/codex";
    category = "llm";
    support = {
      windows = {
        unsupported = "Use the Codex runtime bundled with the Windows ChatGPT desktop app";
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

}
