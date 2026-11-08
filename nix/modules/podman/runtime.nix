{ pkgs }:
let
  inherit (pkgs) lib;
in
rec {
  # Upstream clients still execute "docker" for some operations.
  dockerCompat = pkgs.runCommand "podman-docker-compat" { meta.mainProgram = "docker"; } ''
    mkdir -p "$out/bin"
    ln -s ${lib.getExe pkgs.podman} "$out/bin/docker"
  '';

  apiEnvironment =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''
        if [ -z "''${DOCKER_HOST:-}" ]; then
          if podman_socket=$(${lib.getExe pkgs.podman} machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null); then
            export DOCKER_HOST="unix://$podman_socket"
          fi
        fi
      ''
    else
      ''
        if [ -z "''${DOCKER_HOST:-}" ]; then
          export DOCKER_HOST="unix://''${XDG_RUNTIME_DIR:-/run/user/$(${lib.getExe' pkgs.coreutils "id"} -u)}/podman/podman.sock"
        fi
      '';

  wrap =
    package: executable:
    pkgs.symlinkJoin {
      name = "${package.pname}-podman-${package.version}";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/${executable}" \
          --prefix PATH : ${
            lib.makeBinPath [
              dockerCompat
              pkgs.podman
            ]
          } \
          --run ${lib.escapeShellArg apiEnvironment}
      '';
      inherit (package) meta;
    };
}
