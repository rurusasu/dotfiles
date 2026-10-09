{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  dockerHost = "unix://${config.home.homeDirectory}/.docker/run/docker.sock";
  logDirectory = "${config.home.homeDirectory}/Library/Logs";
  maintenance = pkgs.writeShellApplication {
    name = "tool-cache-maintenance";
    runtimeInputs = [
      pkgs.uv
      pkgs.go
    ];
    text = ''
      status=0

      run_cleanup() {
        local name="$1"
        shift
        printf 'Cleaning %s cache\n' "$name"
        if "$@"; then
          printf 'Finished %s cache cleanup\n' "$name"
        else
          local result=$?
          printf '%s cache cleanup failed (exit %s)\n' "$name" "$result" >&2
          status=1
        fi
      }

      run_cleanup uv uv cache prune
      # Keep downloaded modules and project outputs; rebuild this cache as needed.
      run_cleanup go go clean -cache

      # Cargo already garbage-collects its global cache. Do not sweep project target/.
      if command -v docker >/dev/null 2>&1; then
        # Pin Docker Desktop's local socket, regardless of context/environment overrides.
        if docker --host ${lib.escapeShellArg dockerHost} info --format '{{.ServerVersion}}' >/dev/null; then
          run_cleanup docker docker --host ${lib.escapeShellArg dockerHost} builder prune --force
        else
          printf 'Skipping Docker build cache: local Docker Desktop is unavailable\n' >&2
        fi
      else
        printf 'Skipping Docker build cache: Docker CLI is unavailable\n' >&2
      fi

      exit "$status"
    '';
  };
in
{
  launchd.agents.tool-cache-maintenance = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe maintenance) ];
      EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin";
      StartCalendarInterval =
        if osConfig != null then
          osConfig.nix.gc.interval
        else
          lib.hm.darwin.mkCalendarInterval (builtins.head config.nix.gc.dates);
      RunAtLoad = false;
      ProcessType = "Background";
      StandardOutPath = "${logDirectory}/tool-cache-maintenance.log";
      StandardErrorPath = "${logDirectory}/tool-cache-maintenance.log";
    };
  };

  home.activation.cacheMaintenanceLogDirectory = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
    run mkdir -p -- ${lib.escapeShellArg logDirectory}
  '';
}
