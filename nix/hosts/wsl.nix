{
  pkgs,
  lib,
  ...
}:

let
  inherit (import ./identity.nix { inherit lib; }) user repository;
  fontDirectory = "/usr/local/share/fonts/dotfiles-wslg";
  fontFile = "NotoSansCJK-VF.otf.ttc";
in

{
  imports = [ ./nixos.nix ];

  wsl = {
    enable = true;
    defaultUser = user;
    # Expose Windows D3D12/DXCore libraries through /run/opengl-driver/lib.
    useWindowsDriver = true;

    # WSL owns and protects its existing Windows executable registration.
    # Re-registering it makes systemd-binfmt fail on WSL's read-only status file.
    interop.register = false;

    # NixOS manages /etc/hosts through networking.extraHosts.
    wslConf.network.generateHosts = false;
  };

  # Chrome's process locale is Japanese; keep the system's default language.
  i18n.extraLocales = [ "ja_JP.UTF-8/UTF-8" ];

  # Root evaluates the Windows-mounted, user-owned checkout during rebuild.
  # Own its exact trust declaration here, never by editing Home Manager files.
  programs = {
    git = {
      enable = true;
      config.safe.directory = [ repository ];
    };
    # Home Manager's GTK font setting is read through the settings portal.
    dconf.enable = true;
    # Allow running dynamically linked binaries in WSL (e.g. VS Code Server).
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        wayland
        libxkbcommon
      ];
    };
  };
  assertions = [
    {
      assertion = builtins.substring 0 1 repository == "/" && !(pkgs.lib.hasInfix "*" repository);
      message = "WSL Git trust requires one absolute checkout path without wildcards.";
    }
  ];

  systemd.user = {
    # switch-to-configuration restarts this service for existing user managers.
    # A new WantedBy link alone would only take effect at the next login.
    services.nixos-activation = {
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  environment = {
    etc = {
      # kind nodes mount /etc/containerd/certs.d and use the in-cluster Zot
      # as the mirror for registry.localhost.
      "containerd/certs.d/registry.localhost/hosts.toml".text = ''
        server = "http://registry.localhost"

        [host."http://zot.infra.svc.cluster.local:5080"]
          capabilities = ["pull", "resolve"]
      '';
    };
    systemPackages = with pkgs; [
      nvidia-container-toolkit
    ];
  };

  system.activationScripts = {
    dotfilesHostState.text = ''
      install -d -m 0755 /var/lib/dotfiles
      printf '%s\n' ${lib.escapeShellArg user} > /var/lib/dotfiles/user
    '';

    # WSLg's compositor cannot resolve the user distro's absolute store links.
    # Preserve running applications and copy the real font files into /usr/local.
    wslgFonts = {
      deps = [ "specialfs" ];
      text = ''
        ${pkgs.coreutils}/bin/install -d -m 0755 ${fontDirectory}
        ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/${fontFile} ${fontDirectory}/${fontFile}
        ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Regular.ttf ${fontDirectory}/UDEVGothicNF-Regular.ttf
        ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Bold.ttf ${fontDirectory}/UDEVGothicNF-Bold.ttf
        ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${fontDirectory}/NotoColorEmoji.ttf
      '';
    };

    wslWhoami = {
      text = ''
        mkdir -p /usr/bin
        ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami
      '';
    };

    # Retire only the exact wrapper previously copied by this module. Keep
    # unrelated administrator files and symlinks at this path untouched.
    retireSystemOpWrapper = {
      text = ''
        if [ -f /usr/local/bin/op ] && [ ! -L /usr/local/bin/op ]; then
          # The bash store path can change independently of the wrapper body.
          if ${pkgs.coreutils}/bin/head -n 1 /usr/local/bin/op | \
            ${pkgs.gnugrep}/bin/grep -Eq '^#!/nix/store/[a-z0-9]{32}-bash-[^/]+/bin/bash$' && \
            ${pkgs.coreutils}/bin/tail -n +2 /usr/local/bin/op | \
            ${pkgs.diffutils}/bin/cmp -s ${
              pkgs.writeText "legacy-op-wrapper-body" (
                ''
                  OP_NATIVE="/etc/profiles/per-user/${user}/bin/op"
                  # op run injects secrets into Linux processes — keep on native binary
                  if [ "$1" = "run" ] && [ -x "$OP_NATIVE" ]; then
                    exec "$OP_NATIVE" "$@"
                  fi
                  # Find op.exe via Windows PATH (available in WSL via interop)
                  OP_EXE=$(IFS=:; for p in $PATH; do
                    [ -f "$p/op.exe" ] && echo "$p/op.exe" && break
                  done)
                  if [ -z "$OP_EXE" ]; then
                    echo "[ERROR] op.exe not found in PATH" >&2
                    exit 1
                  fi
                  OP_VARS=$(env | grep ^OP_ | cut -d= -f1 | tr '\n' ':')
                  export WSLENV="''${WSLENV:-}:''${OP_VARS%:}"
                  exec "$OP_EXE" "$@"
                ''
                + "\n"
              )
            } -; then
            ${pkgs.coreutils}/bin/rm -- /usr/local/bin/op
          fi
        fi
      '';
    };

    # Generate CDI spec on each activation so kind worker nodes can mount
    # /etc/cdi and use GPU resources through containerd CDI.
    nvidiaCdi = {
      deps = [ "wslWhoami" ];
      text = ''
        mkdir -p /etc/cdi
        ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk cdi generate \
          --output /etc/cdi/nvidia.yaml 2>/dev/null || true
      '';
    };
  };

  # PAM integration for gnome-keyring: auto-unlocks the keyring on login when a
  # proper PAM session is used. The daemon itself is started by the Home Manager
  # user systemd service in nix/home/wsl.nix to avoid a duplicate
  # instance competing for the org.freedesktop.secrets D-Bus name.
  security.pam.services.login.enableGnomeKeyring = true;

}
