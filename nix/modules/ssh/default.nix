{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.onePassword.ssh;
  githubKnownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  agentSocket =
    if pkgs.stdenv.hostPlatform.isDarwin then
      config.home.homeDirectory + "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
      config.home.homeDirectory + "/.1password/agent.sock";
in
{
  options.dotfiles.onePassword.ssh.publicKey = lib.mkOption {
    type = lib.types.nullOr lib.types.nonEmptyStr;
    default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMpL8l17Y0Lci3Y0ZsgnUz75XiHUrQn5vC6XyHZp7wC";
    description = "SSH public key used for authentication and Git signing. When null, leave the public key file unmanaged.";
  };

  config = lib.mkMerge [
    (lib.mkIf config.programs.ssh.enable {
      programs.ssh = {
        package = pkgs.openssh;
        enableDefaultConfig = false;
        settings."github.com" = lib.mkIf config.dotfiles.onePassword.enable {
          User = "git";
          IdentityFile = ''"${
            lib.escape [ "\\" "\"" ] (config.home.homeDirectory + "/.ssh/signing_key.pub")
          }"'';
          IdentitiesOnly = true;
          UserKnownHostsFile = toString githubKnownHosts;
          StrictHostKeyChecking = true;
        };
      };
    })
    (lib.mkIf config.dotfiles.onePassword.enable {
      # The 1Password desktop provides the agent for every SSH client.
      services.ssh-agent.enable = false;
      services.gpg-agent.enableSshSupport = false;
      home.sessionVariables.SSH_AUTH_SOCK = agentSocket;
      programs.ssh.extraOptionOverrides.IdentityAgent = ''"${agentSocket}"'';
      home.file = lib.mkIf (cfg.publicKey != null) {
        ".ssh/signing_key.pub" = {
          text = "${cfg.publicKey}\n";
          executable = false;
          force = true;
        };
      };
    })
  ];
}
