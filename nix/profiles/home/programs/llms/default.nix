# LLM/AI Tools Installation
# Configs are managed by chezmoi (chezmoi/llms/)
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Claude Code - Anthropic's CLI coding assistant
    claude-code

    # Codex - OpenAI's CLI tool
    codex

    # Gemini CLI - Google's AI assistant
    # gemini-cli  # TODO: Temporarily disabled due to npm cache build issue

    # Cursor CLI - Cursor editor CLI
    cursor-cli
  ];
}
