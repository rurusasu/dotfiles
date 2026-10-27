{ inputs, pkgs }:
let
  inherit (pkgs) lib;
in
rec {
  docker-mcp = pkgs.callPackage ./docker-mcp.nix {
    releaseMetadata = inputs.docker-mcp-release;
  };

  chrome-devtools-mcp =
    inputs.mcp-servers.packages.${pkgs.stdenv.hostPlatform.system}.chrome-devtools-mcp;

  mcp-proxy = pkgs.mcp-proxy.override {
    # The proxy's streamable HTTP server still requires the request_ctx API.
    python3Packages = pkgs.python3Packages.overrideScope (
      _: prev: {
        mcp = prev.mcp_1;
      }
    );
  };

  xurl = pkgs.buildGoModule (finalAttrs: {
    pname = "xurl";
    version = "unstable-${inputs.xurl.shortRev}";
    src = inputs.xurl;
    vendorHash = "sha256-3yUZZYHcDpCaK55uiVw4X9mxvda9iL+XwPpSXheKOSc=";

    subPackages = [ "." ];
    # MCP and authentication work without the optional CGo XChat client.
    env.CGO_ENABLED = 0;

    ldflags = [
      "-s"
      "-w"
      "-X github.com/xdevplatform/xurl/version.Version=${finalAttrs.version}"
    ];

    meta = {
      description = "Command-line tool for the X API";
      homepage = "https://github.com/xdevplatform/xurl";
      license = lib.licenses.mit;
      mainProgram = "xurl";
      platforms = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  });

  hermes-xapi =
    pkgs.runCommand "hermes-xapi"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "hermes-xapi";
      }
      ''
        install -Dm644 ${../../../scripts/sh/install-common.sh} "$out/libexec/hermes-xapi/install-common.sh"
        install -Dm644 ${../../../scripts/sh/hermes-xapi-common.sh} "$out/libexec/hermes-xapi/hermes-xapi-common.sh"
        install -Dm644 ${../../../scripts/sh/hermes-xapi.sh} "$out/libexec/hermes-xapi/hermes-xapi.sh"
        mkdir -p "$out/bin"
        makeWrapper ${lib.getExe pkgs.bash} "$out/bin/hermes-xapi" \
          --add-flags "$out/libexec/hermes-xapi/hermes-xapi.sh" \
          --prefix PATH : ${
            lib.makeBinPath [
              xurl
              pkgs.jq
              pkgs.yq-go
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gawk
            ]
          } \
          --suffix PATH : ${lib.makeBinPath [ pkgs._1password-cli ]}
      '';
}
