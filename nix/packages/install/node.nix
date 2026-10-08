# npm/pnpm global package and adapter metadata.
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

  # Windows pnpm global packages. Unix DSH is owned by its Home Manager module.
  pnpmGlobal = [
    "@deepseek-ai/dsh"
  ];

  # Post-install verification commands for pnpm packages.
  # Keys match globalPackages entries. Packages not listed skip verification.
  pnpmVerify = {
    "@deepseek-ai/dsh" = {
      command = "dsh";
      args = [ "--version" ];
    };
  };

  pnpmPostInstall = { };

  # Extra pnpm install arguments for packages that need approved native builds.
  pnpmInstallArgs = {
    "@deepseek-ai/dsh" = [
      "--allow-build=@deepseek-ai/dsh-subprocess-local"
      "--allow-build=@google/genai"
      "--allow-build=koffi"
      "--allow-build=protobufjs"
      "--allow-build=!node-pty"
    ];
  };

}
