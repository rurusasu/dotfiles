{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
in
{
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr = map (
      home:
      let
        cfg = home.config.programs.codex;
        agentFile = lib.removePrefix "${home.config.home.homeDirectory}/" cfg.settings.agents.fast_worker.config_file;
        activation = home.config.home.activation.codexMutableSettings.data;
        settingsToml = (home.pkgs.formats.toml { }).generate "codex-config" cfg.settings;
        settingsSource = home.pkgs.runCommand "codex-config.toml" { } ''
          settings="$(${lib.getExe home.pkgs.jaq} --from toml --to toml '.' ${settingsToml})"
          printf '%s\n' "$settings" > "$out"
        '';
      in
      {
        enabled = cfg.enable;
        appProvided = cfg.package == null || cfg.package ? chatgpt;
        mutable = cfg.mutableSettings;
        contextSource = home.config.home.file.".codex/AGENTS.override.md".source;
        contextTakeover = home.config.home.file.".codex/AGENTS.override.md".force;
        hooksSource = home.config.home.file.".codex/hooks.json".source.drvPath;
        ruleSources = lib.mapAttrs (
          name: _: home.config.home.file.".codex/rules/${name}.rules".source
        ) cfg.rules;
        agentSource = home.config.home.file.${agentFile}.source;
        mergeActivation = home.config.home.activation ? codexMutableSettings;
        mutableTarget = lib.hasInfix (
          "display_path=" + lib.escapeShellArg "${home.config.home.homeDirectory}/.codex/config.toml"
        ) activation;
        mergesToml = lib.hasInfix "--from toml" activation;
        declaredSettings = lib.hasInfix (builtins.unsafeDiscardStringContext (toString settingsSource)) activation;
        noImmutableConfig = !(home.config.home.file ? ".codex/config.toml");
      }
    ) homes;
    expected = map (
      home:
      let
        cfg = home.config.programs.codex;
      in
      {
        enabled = true;
        appProvided = true;
        mutable = true;
        contextSource = cfg.contextOverride;
        contextTakeover = true;
        hooksSource =
          ((home.pkgs.formats.json { }).generate "codex-hooks" { inherit (cfg) hooks; }).drvPath;
        ruleSources = cfg.rules;
        agentSource = ../../../modules/ai_agents/chatgpt/agents/fast_worker.toml;
        mergeActivation = true;
        mutableTarget = true;
        mergesToml = true;
        declaredSettings = true;
        noImmutableConfig = true;
      }
    ) homes;
  };
}
