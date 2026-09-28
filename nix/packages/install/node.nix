# npm/pnpm global package and adapter metadata.
{ packageInstallTimeoutSeconds }:
{
  # Post-install verification commands for npm packages.
  # Keys match catalog attr names from npmMap.
  npmVerify = {
    codex = {
      command = "codex";
      args = [ "--version" ];
    };
    "agent-browser" = {
      command = "agent-browser";
      args = [ "--version" ];
    };
    devcontainer = {
      command = "devcontainer";
      args = [ "--version" ];
    };
  };

  # Cross-platform pnpm global packages
  pnpmGlobal = [
    "bash-language-server"
    "yaml-language-server"
    "@prisma/language-server"
    "@deepseek-ai/dsh"
    "@playwright/cli@0.1.21"
    "playwright@1.63.0"
    "typescript-language-server"
    "typescript"
  ];

  pnpmInstallFeature = {
    "@playwright/cli" = "WithHermes";
    playwright = "WithHermes";
  };

  # Post-install verification commands for pnpm packages.
  # Keys match globalPackages entries. Packages not listed skip verification.
  pnpmVerify = {
    "bash-language-server" = {
      command = "bash-language-server";
      args = [ "--version" ];
    };
    "yaml-language-server" = {
      command = "yaml-language-server";
      args = [ "--version" ];
    };
    "@prisma/language-server" = {
      command = "prisma-language-server";
      type = "commandExists";
    };
    "@google/gemini-cli" = {
      command = "gemini";
      args = [ "--version" ];
    };
    "typescript-language-server" = {
      command = "typescript-language-server";
      args = [ "--version" ];
    };
    "typescript" = {
      command = "tsc";
      args = [ "--version" ];
    };
    "@deepseek-ai/dsh" = {
      command = "dsh";
      args = [ "--version" ];
    };
    "@playwright/cli" = {
      command = "playwright-cli";
      args = [ "--version" ];
    };
    "playwright" = {
      command = "playwright";
      args = [ "--version" ];
    };
  };

  # Post-install commands for pnpm packages.
  # Playwright keeps browser binaries outside node_modules by default
  # (%LOCALAPPDATA%/ms-playwright on Windows); this ensures the pnpm-managed
  # CLI also provisions the Chromium runtime used by automation scripts.
  pnpmPostInstall = {
    "playwright" = {
      command = "playwright";
      args = [
        "install"
        "chromium"
      ];
      timeoutSeconds = packageInstallTimeoutSeconds;
    };
  };

  # Extra pnpm install arguments for packages that need approved native builds.
  pnpmInstallArgs = {
    "@deepseek-ai/dsh" = [
      "--allow-build=@deepseek-ai/dsh-subprocess-local"
      "--allow-build=@google/genai"
      "--allow-build=koffi"
      "--allow-build=protobufjs"
      "--allow-build=!node-pty"
    ];
    "@google/gemini-cli" = [
      "--allow-build=@github/keytar"
      "--allow-build=!node-pty"
    ];
  };

}
