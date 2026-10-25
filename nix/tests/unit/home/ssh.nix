{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
  sharedSsh = sharedConfig.programs.ssh;
in
{
  testNativeSshOwnsItsConfigWithoutBackups = {
    expr = map (home: {
      sshForce = home.config.home.file.".ssh/config".force;
      sshIncludes = home.config.programs.ssh.includes;
      sshDefaultsDisabled = !home.config.programs.ssh.enableDefaultConfig;
      github = home.config.programs.ssh.settings."github.com".data;
    }) homes;
    expected = map (_: {
      sshForce = true;
      sshIncludes = sharedSsh.includes;
      sshDefaultsDisabled = true;
      github = sharedSsh.settings."github.com".data;
    }) homes;
  };
}
