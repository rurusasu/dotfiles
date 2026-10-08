{ config, pkgs, ... }:
let
  agentSocket =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
      "${config.home.homeDirectory}/.1password/agent.sock";
in
{
  # 1Password provides the agent; do not start a second Home Manager agent.
  services.ssh-agent.enable = false;
  services.gpg-agent.enableSshSupport = false;
  # OpenSSH and other agent clients must use the same desktop-provided socket.
  home.sessionVariables.SSH_AUTH_SOCK = agentSocket;
  programs.ssh.extraOptionOverrides.IdentityAgent = ''"${agentSocket}"'';
}
