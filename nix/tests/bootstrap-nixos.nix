{
  inputs,
  pkgs,
}:
let
  dotfilesSource = ../..;
  helloWorldImage = pkgs.dockerTools.buildImage {
    name = "hello-world";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "hello-world-root";
      paths = [ pkgs.busybox ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/sh"
      "-c"
      "echo Hello from Docker!"
    ];
  };
  acceptanceImage = pkgs.dockerTools.buildImage {
    name = "nginx";
    tag = "1.29-alpine";
    copyToRoot = pkgs.buildEnv {
      name = "acceptance-root";
      paths = [ pkgs.busybox ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/httpd"
      "-f"
      "-p"
      "80"
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "bootstrap-nixos-vm";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        ../hosts/linux/configuration.nix
        ./hardware-configuration.nix
      ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.nixos = {
          home.stateVersion = "25.05";
          programs.home-manager.enable = true;
        };
      };

      environment.systemPackages = with pkgs; [
        nix
        git
        gh
        chezmoi
        ripgrep
        fd
        jq
        neovim
        nodejs_24
        python3
        go
        rustup
        netcat
      ];

      virtualisation = {
        diskSize = 8192;
        memorySize = 4096;
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # NixOS tests disable switch-to-configuration by default to reduce
      # rebuilds. This E2E intentionally activates the generated closure.
      system.switch.enable = true;
    };

  testScript = { nodes, ... }: ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("docker.service")
    machine.succeed("docker load < ${helloWorldImage}")
    machine.succeed("docker load < ${acceptanceImage}")
    machine.succeed("cp -r ${dotfilesSource} /home/nixos/dotfiles")
    machine.succeed("chmod -R u+w /home/nixos/dotfiles && chown -R nixos:users /home/nixos/dotfiles")

    install = "su - nixos -c 'env DOTFILES_NIXOS_PREBUILT_SYSTEM=${nodes.machine.system.build.toplevel} DOTFILES_NIXOS_HARDWARE_CONFIG=/etc/nixos/hardware-configuration.nix DOTFILES_CHECKOUT_TARGET=/home/nixos/dotfiles /home/nixos/dotfiles/.github/e2e/run-bootstrap-acceptance.sh'"
    machine.succeed(install)
    machine.succeed(install)
    machine.succeed("su - nixos -c 'export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/nixos/bin:$HOME/.nix-profile/bin:$PATH; cd /home/nixos/dotfiles; DOTFILES_VERIFY_SYSTEM_LAYER=nixos ./scripts/sh/verify-environment.sh --runtime'")
    machine.succeed("docker compose -f /home/nixos/dotfiles/docker/hermes-agent/compose.yml ps --status running --services | grep acceptance")
  '';
}
