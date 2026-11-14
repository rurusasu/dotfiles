{
  inputs,
  pkgs,
  code,
  files,
  fixtures,
}:
let
  proxy = (code.nix.modules.ai_agents.mcp-packages { inherit inputs pkgs; }).mcp-proxy;
  python = pkgs.python3.withPackages (packages: [
    packages.mcp_1
    packages.httpx
  ]);
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    { home.homeDirectory = "/mcp-fixture-home"; }
  ];
in
{
  shared-mcp-auth =
    pkgs.runCommand "shared-mcp-auth-check" { __darwinAllowLocalNetworking = true; }
      ''
        export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        ${python}/bin/python3 ${
          files.nix.tests.build.modules.ai_agents.mcp."auth.py"
        } ${pkgs.lib.getExe proxy} ${home.config.programs.mcp.servers.chrome.command} \
          ${home.config.home.homeDirectory}
        touch "$out"
      '';
}
