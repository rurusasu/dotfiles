{
  # Native desktop and the CLI shipped in the same official distribution.
  packages =
    { pkgs }:
    let
      # Upstream otherwise replaces these binaries with its separate Codex package.
      chatgpt = pkgs.chatgpt.override { codex = null; };
      resources =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${chatgpt}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin"
        else
          "${chatgpt}/lib/chatgpt/resources";
    in
    assert pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin;
    {
      inherit chatgpt;
      codex = pkgs.linkFarm "codex" (
        {
          "bin/codex" = "${resources}/codex";
          "bin/codex-code-mode-host" = "${resources}/codex-code-mode-host";
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          "bin/bwrap" = pkgs.lib.getExe pkgs.bubblewrap;
        }
      );
    };

  homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.activation.codexXdgHome = lib.mkIf config.home.preferXdgDirectories (
        lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
          legacy=${lib.escapeShellArg "${config.home.homeDirectory}/.codex"}
          target=${lib.escapeShellArg "${config.xdg.configHome}/codex"}
          if [[ -L "$legacy" ]]; then
            if [[ "$(${pkgs.coreutils}/bin/readlink -m -- "$legacy")" != "$(${pkgs.coreutils}/bin/readlink -m -- "$target")" ]]; then
              errorEcho "Codex legacy directory points elsewhere: $legacy; reconcile it with $target before activating."
              exit 1
            fi
          elif [[ -e "$legacy" ]]; then
            if [[ ! -d "$legacy" || -e "$target" || -L "$target" ]]; then
              errorEcho "Cannot migrate Codex state from $legacy to $target without overwriting existing data."
              exit 1
            fi
            run ${pkgs.coreutils}/bin/mkdir -p -- "$(${pkgs.coreutils}/bin/dirname -- "$target")"
            run ${pkgs.coreutils}/bin/mv --no-target-directory --update=none-fail -- "$legacy" "$target"
          fi
          if [[ ! -e "$legacy" && ! -L "$legacy" ]]; then
            run ${pkgs.coreutils}/bin/mkdir -p -- "$target"
            run ${pkgs.coreutils}/bin/ln -s -- "$target" "$legacy"
          fi
        ''
      );

      # The mutable merge retains omitted keys, including removed managed roles.
      home.activation.codexPruneManagedAgents =
        lib.hm.dag.entryBetween [ "codexMutableSettings" ] [ "linkGeneration" ]
          (
            lib.hm.generators.mkImpureConfigMerger {
              inherit pkgs;
              format = "toml";
              empty = "{}";
              jqOperation = ''
                $dynamic | reduce ["fast_worker", "python_coding"][] as $name (.;
                  if .agents[$name].config_file? == (${builtins.toJSON "${config.home.homeDirectory}/.codex/agents/"} + $name + ".toml")
                  then del(.agents[$name]) else . end)
              '';
              path = "${
                if config.home.preferXdgDirectories then
                  "${config.xdg.configHome}/codex"
                else
                  "${config.home.homeDirectory}/.codex"
              }/config.toml";
              staticSettings = pkgs.writeText "codex-agent-migration.toml" "";
              mode = "600";
            }
          );

      programs.codex = {
        enable = true;
        enableMcpIntegration = true;
        # tools.nix exposes the bundled CLI; Home Manager only manages settings.
        package = lib.mkDefault null;
        # Preserve application settings and project trust in a writable user file.
        mutableSettings = true;
        settings = {
          model = "gpt-6.1-sol";
          model_reasoning_effort = "high";
          plan_mode_reasoning_effort = "high";
          model_reasoning_summary = "auto";
          model_verbosity = "low";
          approval_policy = "never";
          default_permissions = ":danger-full-access";
          web_search = "live";
          features = {
            # The app-bundled CLI lacks the complete package layout required by
            # the managed daemon; keep interactive sessions in embedded mode.
            daemon_auto_start = false;
            unified_exec = true;
            apps = true;
          };
          tui.keymap.editor.insert_newline = [
            "shift-enter"
            "ctrl-enter"
            "ctrl-j"
          ];
          tools.view_image = true;
          plugins =
            lib.genAttrs
              (map (name: "${name}@openai-curated") [
                "slack"
                "github"
                "hugging-face"
                "codex-security"
                "openai-developers"
              ])
              (_: {
                enabled = true;
              })
            // {
              "linear@openai-curated".enabled = false;
              "notion@openai-curated".enabled = false;
            };
          # Native desktop cleanup: protected worktrees and snapshots remain upstream-owned.
          desktop = {
            worktree-auto-cleanup-enabled = true;
            worktree-keep-count = 15;
          };
        };
      };
    };
}
