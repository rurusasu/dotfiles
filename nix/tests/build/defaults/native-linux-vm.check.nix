{
  inputs,
  pkgs,
  code,
}:
let
  inherit (pkgs) lib;
  # Register every locked source in the guest store. Retain the original lock
  # metadata (including lastModified), rather than replacing dependencies with
  # path inputs whose normalized timestamps can change package versions.
  sources = lib.genericClosure {
    startSet = map (input: {
      key = toString input.outPath;
      inherit input;
    }) (builtins.attrValues (removeAttrs inputs [ "self" ]));
    operator =
      entry:
      map (input: {
        key = toString input.outPath;
        inherit input;
      }) (builtins.attrValues (entry.input.inputs or { }));
  };
  preparedFlake = pkgs.writeTextDir "flake.nix" ''
    {
      inputs.dotfiles = ${
        lib.generators.toPretty { } {
          url = "path:${inputs.self.outPath}${
            lib.optionalString (inputs.self ? rev) "?rev=${inputs.self.rev}"
          }";
        }
      };
      outputs = { dotfiles, ... }: {
        nixosConfigurations.linux =
          dotfiles.checks.x86_64-linux.native-linux-vm.productionConfiguration;
      };
    }
  '';
  hermesEnv = pkgs.writeText "native-linux-hermes.env" ''
    OPENROUTER_API_KEY=ci
    API_SERVER_ENABLED=true
    API_SERVER_KEY=dotfiles-ci-health-probe
    API_SERVER_PORT=18642
  '';
in
lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  native-linux-vm = pkgs.testers.runNixOSTest (
    { config, ... }:
    {
      name = "dotfiles-native-linux";
      node = {
        pkgs = lib.mkForce null;
        specialArgs = {
          inherit inputs;
          platform = "linux";
        };
      };
      # The driver is the immutable producer artifact. CI builds `.driver` and
      # runs it in the E2E stage, rather than executing this check twice.
      passthru.productionConfiguration = {
        config = config.nodes.machine.specialisation.production.configuration;
      };
      nodes.machine = {
        nixpkgs.overlays = [
          (_final: prev: {
            lkl = prev.lkl.overrideAttrs (old: {
              # cptofs hardcodes 100 MiB, which exhausts memory while copying
              # the production closure. Give only this image-copy tool 1 GiB.
              postPatch = (old.postPatch or "") + ''
                substituteInPlace tools/lkl/cptofs.c \
                  --replace-fail 'lkl_start_kernel("mem=100M")' 'lkl_start_kernel("mem=1024M")'
              '';
            });
            vmTools = prev.vmTools // {
              runInLinuxVM =
                drv:
                prev.vmTools.runInLinuxVM (
                  if drv.name == "nixos-disk-image" then
                    drv.overrideAttrs (old: {
                      # cptofs has copied the closure into the raw image. Free
                      # its staging copy before the raw-to-qcow2 conversion.
                      preVM = old.preVM + ''
                        test "$root" = "$PWD/root"
                        find "$root" -type d -exec chmod u+w {} +
                        rm -rf -- "$root"
                      '';
                    })
                  else
                    drv
                );
            };
          })
        ];
        virtualisation = {
          memorySize = 4096;
          cores = 2;
          writableStore = true;
          useBootLoader = true;
          # Bootloader images neither share the host store nor automatically
          # copy paths referenced only by the host-side test script.
          additionalPaths = [
            preparedFlake
            inputs.self.outPath
          ]
          ++ map (entry: entry.input.outPath) sources;
        };
        boot.loader.grub.enable = true;
        users.users.nixos = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };
        security.sudo.wheelNeedsPassword = false;
        environment.systemPackages = with pkgs; [
          gitMinimal
          nixos-rebuild
          curl
          jq
        ];
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          # Source builds in the consumer indicate a missing producer output.
          max-jobs = lib.mkForce 0;
          builders = lib.mkForce "";
        };
        systemd.tmpfiles.rules = [
          "d /home/nixos/.hermes 0700 nixos users -"
          "C /home/nixos/.hermes/.env 0600 nixos users - ${hermesEnv}"
        ];
        specialisation.production.configuration = {
          imports = [ code.nix.hosts.default ];
          # Keep the real Home Manager/service implementation and supply public
          # CI credentials instead of depending on a personal 1Password vault.
          home-manager.users.nixos = {
            programs.mcp.servers = lib.mkForce { };
            services.hermes-agent.settings.secrets.onepassword.enabled = lib.mkForce false;
          };
        };
      };
      testScript =
        { nodes, ... }:
        let
          target = nodes.machine.specialisation.production.configuration.system.build.toplevel;
        in
        ''
          import shlex

          machine.start(allow_reboot=True)
          machine.wait_for_unit("multi-user.target")
          machine.succeed("test ! -e /etc/profiles/per-user/nixos/bin/hermes")
          machine.succeed("cp -a ${inputs.self.outPath} /home/nixos/dotfiles; cp -a ${preparedFlake} /home/nixos/ci-target; chmod -R u+w /home/nixos/dotfiles /home/nixos/ci-target; chown -R nixos:users /home/nixos/dotfiles /home/nixos/ci-target")
          # Lock the fixture's exact local source inputs; this neither updates a
          # production input nor downloads/builds anything in the consumer.
          machine.succeed("su - nixos -c 'nix flake lock --offline /home/nixos/ci-target'")
          before_lock = machine.succeed("sha256sum /home/nixos/dotfiles/flake.lock")
          machine.succeed("su - nixos -c 'DOTFILES_ALLOW_BUILDS=false DOTFILES_FLAKE_REF=path:/home/nixos/ci-target#linux /home/nixos/dotfiles/install.sh'", timeout=1800)
          assert before_lock == machine.succeed("sha256sum /home/nixos/dotfiles/flake.lock")
          machine.succeed("test $(readlink -f /run/current-system) = ${target}")
          boot_id = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
          machine.reboot()
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("home-manager-nixos.service")
          assert boot_id != machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
          machine.succeed("test $(readlink -f /run/current-system) = ${target}")
          machine.wait_for_unit("hermes-agent.service", user="nixos", timeout=360)
          machine.succeed("su - nixos -c " + shlex.quote("GH_TOKEN=ci TAVILY_API_KEY=ci GITHUB_WORK_TOKEN=ci zsh -ic 'hermes --version'"))
          machine.wait_until_succeeds("curl --fail --silent --max-time 2 -H 'Authorization: Bearer dotfiles-ci-health-probe' http://127.0.0.1:18642/health/detailed | jq -e '.status == \"ok\" and .readiness.status == \"ok\" and (.readiness.checks | type == \"object\" and all(.[]; .status == \"ok\")) and (.readiness.checks as $checks | all([\"state_db\", \"session_store\", \"config\", \"model\", \"disk\", \"gateway\", \"background_queues\"][]; . as $required | $checks[$required].status == \"ok\"))'", timeout=360)
        '';
    }
  );
}
