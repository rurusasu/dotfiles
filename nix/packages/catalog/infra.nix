# Package identities and provider declarations for infra.
{ pkgs, ... }:
{
  go-task = {
    pkg = pkgs.go-task;
    winget = "Task.Task";
    category = "infra";
  };

  treefmt = {
    pkg = pkgs.treefmt;
    winget = null;
    category = "infra";
  };

  pre-commit = {
    pkg = pkgs.pre-commit;
    winget = null;
    category = "infra";
  };

  powershell = {
    pkg = pkgs.powershell;
    winget = "Microsoft.PowerShell";
    category = "infra";
  };

  google-cloud-sdk = {
    pkg = pkgs.google-cloud-sdk;
    winget = "Google.CloudSDK";
    category = "infra";
  };
}
