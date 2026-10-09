{
  config,
  lib,
  pkgs,
  ...
}:
let
  account = "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
  publicKeyReference = "op://Private/xnoq6xbcdktkph76e2bg37ou6y/public key";
  readTimeoutSeconds =
    (builtins.fromJSON (builtins.readFile ../../../chezmoi/.chezmoidata/onepassword.json))
    .op_read_timeout_seconds;
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

  # Read only the public field at activation time, never during Nix evaluation
  # or ordinary shell startup. Home Manager's run helper honours dry runs.
  home.activation.onePasswordSshPublicKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run env OP_BIOMETRIC_UNLOCK_ENABLED="''${OP_BIOMETRIC_UNLOCK_ENABLED:-true}" \
      PATH="${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.openssh
          pkgs._1password-cli
        ]
      }:$PATH" \
      ${pkgs.bash}/bin/bash ${./sync-ssh-public-key.sh} ${
        lib.escapeShellArgs [
          "${config.home.homeDirectory}/.ssh/signing_key.pub"
          account
          publicKeyReference
          (toString readTimeoutSeconds)
        ]
      }
  '';
}
