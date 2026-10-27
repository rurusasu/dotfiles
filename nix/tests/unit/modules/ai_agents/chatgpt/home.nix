{ homeConfigurations, upstream }:
let
  inherit (homeConfigurations) homes lib;
in
{
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr = map (
      home:
      let
        cfg = home.config.programs.codex;
        codexHome = "${home.config.xdg.configHome}/codex";
        configDir = lib.removePrefix home.config.home.homeDirectory codexHome;
        activation = home.config.home.activation.codexMutableSettings.data;
      in
      {
        inherit (cfg) contextOverride hooks rules;
        enabled = cfg.enable;
        appProvided = cfg.package == null || cfg.package ? chatgpt;
        mutable = cfg.mutableSettings;
        mcpIntegration = cfg.enableMcpIntegration;
        mcpServers = builtins.attrNames home.config.programs.mcp.servers;
        googlePluginsConfigured =
          map (name: builtins.hasAttr "${name}@openai-curated" cfg.settings.plugins)
            [
              "gmail"
              "google-calendar"
              "google-drive"
            ];
        managesContextOverride = builtins.hasAttr "${configDir}/AGENTS.override.md" home.config.home.file;
        agentsConfigured = cfg.settings ? agents;
        hooksFeatureConfigured = cfg.settings.features ? hooks;
        managedAgentRuleAndHookFiles = builtins.filter (
          name:
          name == "${configDir}/hooks.json"
          || lib.hasPrefix "${configDir}/hooks/" name
          || lib.hasPrefix "${configDir}/rules/" name
          || lib.hasPrefix "${configDir}/agents/" name
        ) (builtins.attrNames home.config.home.file);
        mergeActivation = home.config.home.activation ? codexMutableSettings;
        prunesManagedAgentsBeforeMerge =
          builtins.elem "codexMutableSettings" home.config.home.activation.codexPruneManagedAgents.before
          && builtins.elem "linkGeneration" home.config.home.activation.codexPruneManagedAgents.after;
        mutableTarget = lib.hasInfix (
          "display_path=" + lib.escapeShellArg "${codexHome}/config.toml"
        ) activation;
        mergesToml = lib.hasInfix "--from toml" activation;
        declaredSettings = lib.hasInfix (builtins.unsafeDiscardStringContext (
          toString (
            home.pkgs.runCommand "codex-config.toml" { } ''
              settings="$(${lib.getExe home.pkgs.jaq} --from toml --to toml '.' ${
                (home.pkgs.formats.toml { }).generate "codex-config" (
                  cfg.settings
                  // {
                    mcp_servers =
                      (lib.mapAttrs (
                        _: server:
                        (upstream.home-manager.code.modules.lib.mcp { inherit lib; }).transformMcpServer {
                          inherit server;
                          exclude = [
                            "headers"
                            "type"
                          ];
                        }
                      ) home.config.programs.mcp.servers)
                      // (cfg.settings.mcp_servers or { });
                  }
                )
              })"
              printf '%s\n' "$settings" > "$out"
            ''
          )
        )) activation;
        noImmutableConfig = !(builtins.hasAttr "${configDir}/config.toml" home.config.home.file);
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      appProvided = true;
      mutable = true;
      mcpIntegration = true;
      mcpServers = [
        "MCP_DOCKER"
        "chrome"
        "pipedream"
        "xapi"
      ];
      googlePluginsConfigured = [
        false
        false
        false
      ];
      contextOverride = null;
      managesContextOverride = false;
      hooks = { };
      rules = { };
      agentsConfigured = false;
      hooksFeatureConfigured = false;
      managedAgentRuleAndHookFiles = [ ];
      mergeActivation = true;
      prunesManagedAgentsBeforeMerge = true;
      mutableTarget = true;
      mergesToml = true;
      declaredSettings = true;
      noImmutableConfig = true;
    }) homes;
  };
}
