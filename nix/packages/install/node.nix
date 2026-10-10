# npm/pnpm global package and adapter metadata.
{
  # Post-install verification commands for npm packages.
  # Keys match catalog attr names from npmMap.
  npmVerify = {
    dsh = {
      command = "dsh";
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

  # No declared packages require pnpm.
  pnpmGlobal = [ ];
  pnpmVerify = { };
  pnpmPostInstall = { };
  pnpmInstallArgs = { };
}
