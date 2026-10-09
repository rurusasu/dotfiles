{
  inputs,
  pkgs,
}:
let
  dotfilesSource = ../../..;
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
  # The NixOS VM intentionally has no external DNS. Keep the acceptance test
  # focused on the npm installation boundary with a local npm fixture; real
  # registry access is covered by the Linux, macOS, Windows, and consistency
  # jobs.
  offlineNpm = pkgs.writeShellScript "dotfiles-offline-npm" ''
    #!/bin/sh
    set -eu
    prefix="''${NPM_CONFIG_PREFIX:-$HOME/.local/npm}"
    mkdir -p "$prefix/bin"
    printf '#!/bin/sh\nprintf "codex 0.0.0-offline\\n"\n' > "$prefix/bin/codex"
    chmod 0755 "$prefix/bin/codex"
  '';
in
pkgs.testers.runNixOSTest {
  name = "bootstrap-nixos-vm";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        ../../hosts/shared/nixos/configuration.nix
        ../fixtures/hardware-configuration.nix
      ];

      programs.zsh.enable = true;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        sharedModules = [ inputs.hermes-agent.homeManagerModules.default ];
        users.nixos = {
          home.stateVersion = "25.05";
          programs.home-manager.enable = true;
          programs.hermes-agent.enable = true;
          services.hermes-agent = {
            enable = true;
            gateway.enable = true;
            settings.model.default = "openrouter/auto";
            # Test-only credentials: the offline VM never makes provider calls.
            hermesHomeFiles.".env" = ''
              OPENROUTER_API_KEY=ci
              API_SERVER_ENABLED=true
              API_SERVER_KEY=dotfiles-ci-health-probe
              API_SERVER_PORT=18642
            '';
          };
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
        go-task
        neovim
        nodejs
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
    machine.succeed("install -d /home/nixos/ci-bin && install -m 0755 ${offlineNpm} /home/nixos/ci-bin/npm")

    # Keep registry access offline while exercising the native Hermes service.
    machine.succeed("su - nixos -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user start hermes-agent.service'")
    machine.wait_until_succeeds("su - nixos -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active --quiet hermes-agent.service'")
    install = "su - nixos -c 'env XDG_RUNTIME_DIR=/run/user/$(id -u) DOTFILES_NPM_COMMAND=/home/nixos/ci-bin/npm DOTFILES_SKIP_FLAKE_UPDATE=1 DOTFILES_NIXOS_PREBUILT_SYSTEM=${nodes.machine.system.build.toplevel} DOTFILES_NIXOS_HARDWARE_CONFIG=/etc/nixos/hardware-configuration.nix DOTFILES_CHECKOUT_TARGET=/home/nixos/dotfiles /home/nixos/dotfiles/.github/e2e/run-bootstrap-acceptance.sh'"
    machine.succeed(install)
    machine.succeed("su - nixos -c 'bash /home/nixos/dotfiles/.github/e2e/start-bootstrap-runtime.sh'")
    machine.succeed(install)
    machine.succeed("su - nixos -c 'bash /home/nixos/dotfiles/.github/e2e/start-bootstrap-runtime.sh'")
    machine.succeed("su - nixos -c 'export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/nixos/bin:$HOME/.nix-profile/bin:$PATH; cd /home/nixos/dotfiles; DOTFILES_VERIFY_SYSTEM_LAYER=nixos ./scripts/sh/verify-environment.sh --runtime'")
    machine.succeed("docker compose -f /home/nixos/dotfiles/docker/hermes-service/compose.yml ps --status running --services | grep acceptance")
  '';
}
