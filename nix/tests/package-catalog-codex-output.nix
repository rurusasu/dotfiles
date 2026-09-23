{ inputs }:
let
  system = "aarch64-darwin";
in
{
  testRepositoryCodexOutputUsesMaintainedPackageInput = {
    expr = inputs.self.packages.${system}.codex.drvPath;
    expected = inputs.llm-agents.packages.${system}.codex.drvPath;
  };
}
