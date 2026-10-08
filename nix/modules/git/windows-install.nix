let
  gitId = "Git.Git";
  ghqId = "x-motemen.ghq";
  support = identity: {
    windows = {
      provider = "winget";
      source = "winget";
      inherit identity;
    };
    darwin.unsupported = "Unix installation is owned by the Git Home Manager module";
    linux.unsupported = "Unix installation is owned by the Git Home Manager module";
  };
in
{
  windowsOnly = [
    gitId
    ghqId
  ];
  windowsOnlySupport = {
    ${gitId} = support gitId;
    ${ghqId} = support ghqId;
  };
  wingetVerifyById = {
    ${gitId} = {
      command = "git";
      args = [ "--version" ];
    };
    ${ghqId} = {
      command = "ghq";
      args = [ "--version" ];
    };
  };
}
