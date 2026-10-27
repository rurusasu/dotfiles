{
  pkgs,
  fixtures,
  upstream,
}:
{
  hermes-configuration = (
    let
      inherit (pkgs) lib;
    in
    pkgs.runCommand "hermes-configuration-check"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e '
          (.chrome.url == "http://127.0.0.1:8765/mcp")
          and (.chrome | has("command") | not)
          and (.xapi.url == "http://127.0.0.1:8766/mcp")
          and (.xapi | has("command") | not)
          and (.pipedream.url == "https://mcp.pipedream.net/v2")
          and (.pipedream.auth == "oauth")
          and (.pipedream | has("command") | not)
        ' ${
          pkgs.writeText "hermes-mcp-configuration.json" (
            builtins.toJSON (
              lib.genAttrs
                [
                  "chrome"
                  "xapi"
                  "pipedream"
                ]
                (
                  name:
                  (upstream.home-manager.code.modules.lib.mcp { inherit lib; }).transformMcpServer {
                    server =
                      (fixtures.mkHome pkgs.stdenv.hostPlatform.system [
                        {
                          xdg.enable = true;
                          programs.mcp.enable = true;
                        }
                      ]).config.programs.mcp.servers.${name};
                  }
                )
            )
          )
        }
        touch "$out"
      ''
  );
}
