{ inputs }:
{
  testCodexPackageInputProvidesDarwinPackage = {
    expr =
      builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+$" inputs.llm-agents.packages.aarch64-darwin.codex.version
      != null;
    expected = true;
  };
}
