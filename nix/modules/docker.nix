{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  enabled =
    config.homebrew.enable && builtins.any (cask: cask.name == "docker-desktop") config.homebrew.casks;
  appPath = "/Applications/Docker.app";
in
{
  config =
    if options ? homebrew then
      {
        # Homebrew installs the declared cask before postActivation. This host accepts
        # the Docker Desktop license as part of its initial system configuration.
        system.activationScripts.postActivation.text = lib.mkIf enabled (
          lib.mkAfter ''
            (
              set -e
              docker_installer=${lib.escapeShellArg "${appPath}/Contents/MacOS/install"}
              docker_state_dir=${lib.escapeShellArg "${home}/.config/dotfiles"}
              docker_setup_marker="$docker_state_dir/docker-desktop-installed"
              md5_binary=/sbin/md5
              md5_link=/usr/local/bin/md5

              if [[ ! -x $docker_installer ]]; then
                printf 'Docker Desktop installer not found: %s\n' "$docker_installer" >&2
                exit 1
              fi
              if [[ ! -x $md5_binary ]]; then
                printf 'macOS md5 executable is unavailable: %s\n' "$md5_binary" >&2
                exit 1
              fi
              if [[ -L $md5_link && $(/usr/bin/readlink "$md5_link") == "$md5_binary" ]]; then
                :
              elif [[ -e $md5_link || -L $md5_link ]]; then
                printf 'Docker Desktop md5 compatibility path conflicts with existing entry: %s\n' "$md5_link" >&2
                exit 1
              else
                /bin/mkdir -p /usr/local/bin
                /bin/ln -s "$md5_binary" "$md5_link"
              fi

              # Keep existing installer markers, and mark success only after setup.
              if [[ ! -f $docker_setup_marker ]]; then
                echo 'Configuring Docker Desktop and accepting its license...'
                "$docker_installer" --accept-license --user=${lib.escapeShellArg user}
                /usr/bin/sudo -u ${lib.escapeShellArg user} -- /bin/mkdir -p "$docker_state_dir"
                /usr/bin/sudo -u ${lib.escapeShellArg user} -- /usr/bin/touch "$docker_setup_marker"
              fi
            )
          ''
        );
      }
    else
      {
        # Preserve the existing native NixOS and WSL daemon policies.
        environment.systemPackages = lib.optionals (!(config ? wsl && config.wsl.enable)) [
          pkgs.docker-compose
          pkgs.docker-buildx
        ];
        virtualisation.docker = {
          enable = true;
          daemon.settings =
            if config ? wsl && config.wsl.enable then
              { insecure-registries = [ "registry.localhost" ]; }
            else
              {
                "log-driver" = "json-file";
                "log-opts" = {
                  "max-size" = "10m";
                  "max-file" = "3";
                };
              };
        };
      };
}
