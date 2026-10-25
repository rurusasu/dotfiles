{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
in
{
  testNativeSshOwnsItsConfigWithoutBackups = {
    expr = map (
      home:
      let
        cfg = home.config.programs.ssh;
        text = home.config.home.file.".ssh/config".text;
        github = cfg.settings."github.com".data;
        renderValue =
          value: if builtins.isBool value then (if value then "yes" else "no") else toString value;
        githubLines = [
          github.header
        ]
        ++ lib.mapAttrsToList (name: value: "  ${name} ${renderValue value}") (
          builtins.removeAttrs github [ "header" ]
        );
      in
      {
        sshForce = home.config.home.file.".ssh/config".force;
        includesRendered =
          cfg.includes == [ ]
          || lib.hasInfix (builtins.unsafeDiscardStringContext "Include ${lib.concatStringsSep " " cfg.includes}") text;
        sshDefaultsDisabled = !cfg.enableDefaultConfig;
        githubRendered = builtins.all (line: builtins.elem line (lib.splitString "\n" text)) githubLines;
      }
    ) homes;
    expected = map (_: {
      sshForce = true;
      includesRendered = true;
      sshDefaultsDisabled = true;
      githubRendered = true;
    }) homes;
  };
}
