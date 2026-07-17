{
  inputs,
  pkgs,
}:
let
  inherit (pkgs) lib;
  dotfilesSource = ../..;
  inputSources = lib.filter (source: source != null) (
    lib.mapAttrsToList (_: input: input.outPath or null) inputs
  );
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

      virtualisation = {
        diskSize = 8192;
        memorySize = 4096;
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      system.extraDependencies = inputSources ++ [ dotfilesSource ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("docker.service")
    machine.succeed("docker load < ${helloWorldImage}")
    machine.succeed("docker load < ${acceptanceImage}")

    install = "su - nixos -c 'env DOTFILES_NIXOS_HARDWARE_CONFIG=/etc/nixos/hardware-configuration.nix DOTFILES_COMPOSE_FILE=${dotfilesSource}/.github/e2e/bootstrap-compose.yml DOTFILES_CHECKOUT_TARGET=${dotfilesSource} ${dotfilesSource}/install.sh'"
    machine.succeed(install)
    machine.succeed(install)
    machine.succeed("su - nixos -c 'export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/nixos/bin:$HOME/.nix-profile/bin:$PATH; cd ${dotfilesSource}; sg docker -c \"DOTFILES_VERIFY_SYSTEM_LAYER=nixos DOTFILES_COMPOSE_FILE=${dotfilesSource}/.github/e2e/bootstrap-compose.yml ./scripts/sh/verify-environment.sh --runtime\"'")
    machine.succeed("docker compose -f ${dotfilesSource}/.github/e2e/bootstrap-compose.yml ps --status running --services | grep acceptance")
  '';
}
