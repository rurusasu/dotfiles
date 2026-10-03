{ homeDirectory, isDarwin }:
# 言語サーバーごとの Cursor 拡張設定。実行ファイルは通常の PATH を使う。
{
  "nix.enableLanguageServer" = true;
  "nix.serverPath" = "nixd";
  "ruff.nativeServer" = "on";
  "ruff.enable" = true;
  "ruff.path" = [ "ruff" ];
  "ruff.configuration" = "\${workspaceFolder}/pyproject.toml";
  "ruff.lint.run" = "onSave";
  "ruff.lint.preview" = true;
  "ruff.organizeImports" = true;
  "ruff.fixAll" = true;
  "ruff.format.preview" = true;
  "ruff.showNotifications" = "onError";
  "ruff.codeAction.fixViolation.enable" = true;
  "ruff.codeAction.disableRuleComment.enable" = true;
  "python.languageServer" = "None";
  "ty.enable" = true;
  "ty.configuration" = "\${workspaceFolder}/pyproject.toml";
  "ty.disableLanguageServices" = false;
  "ty.completions.autoImport" = true;
  "ty.logLevel" = "info";
  "go.useLanguageServer" = true;
  "gopls" = {
    "ui.semanticTokens" = true;
    "ui.completion.usePlaceholders" = true;
    "staticcheck" = true;
    "formatting.gofumpt" = true;
    "analyses" = {
      "unusedparams" = true;
      "shadow" = true;
      "nilness" = true;
      "unusedwrite" = true;
      "useany" = true;
    };
    "hints" = {
      "assignVariableTypes" = true;
      "compositeLiteralFields" = true;
      "compositeLiteralTypes" = true;
      "constantValues" = true;
      "functionTypeParameters" = true;
      "parameterNames" = true;
      "rangeVariableTypes" = true;
    };
  };
  "rust-analyzer.checkOnSave" = true;
  "rust-analyzer.check.command" = "clippy";
  "rust-analyzer.cargo.allFeatures" = true;
  "rust-analyzer.cargo.buildScripts.enable" = true;
  "rust-analyzer.procMacro.enable" = true;
  "rust-analyzer.inlayHints.bindingModeHints.enable" = true;
  "rust-analyzer.inlayHints.closureCaptureHints.enable" = true;
  "rust-analyzer.inlayHints.closureReturnTypeHints.enable" = "always";
  "rust-analyzer.inlayHints.lifetimeElisionHints.enable" = "skip_trivial";
  "rust-analyzer.inlayHints.typeHints.hideNamedConstructor" = false;
  "typescript.inlayHints.parameterNames.enabled" = "all";
  "typescript.inlayHints.parameterTypes.enabled" = true;
  "typescript.inlayHints.variableTypes.enabled" = true;
  "typescript.inlayHints.propertyDeclarationTypes.enabled" = true;
  "typescript.inlayHints.functionLikeReturnTypes.enabled" = true;
  "typescript.inlayHints.enumMemberValues.enabled" = true;
  "ty.path" = [ "ty" ];
  "rust-analyzer.server.path" = "rust-analyzer";
  "go.alternateTools" = {
    "gopls" = "gopls";
  };
}
// {
  "nix.serverSettings".nixd = {
    formatting.command = [ "nixfmt" ];
    options =
      if isDarwin then
        {
          darwin.expr = "(builtins.getFlake \"${homeDirectory}/.dotfiles\").darwinConfigurations.macos.options";
        }
      else
        {
          nixos.expr = "(builtins.getFlake \"${homeDirectory}/.dotfiles\").nixosConfigurations.nixos.options";
        };
  };
}
