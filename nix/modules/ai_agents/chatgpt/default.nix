{
  config,
  lib,
  pkgs,
  ...
}:
let
  resources =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.programs.chatgpt.package}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin"
    else
      "${config.programs.chatgpt.package}/lib/chatgpt/resources";
in
{
  options.programs.chatgpt = {
    enable = lib.mkEnableOption "ChatGPT desktop with its bundled Codex CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.chatgpt.override {
        codex = null;
        # Remove after nixpkgs-unstable includes nixpkgs 743696b736aa419c86abb36e2777cda684d619a0.
        tectonic-unwrapped = pkgs.tectonic-unwrapped.overrideAttrs (previous: {
          buildInputs = [ pkgs.aws-lc ] ++ previous.buildInputs;
        });
      };
      defaultText = lib.literalMD "nixpkgs ChatGPT with its bundled Codex CLI and the upstream Tectonic build fix";
      description = "ChatGPT desktop distribution providing the bundled Codex CLI.";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf config.programs.chatgpt.enable {
      programs.codex.enable = true;
      home.packages = [ config.programs.chatgpt.package ];
    })
    (lib.mkIf config.programs.codex.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin;
          message = "The ChatGPT-bundled Codex CLI requires Linux or macOS.";
        }
      ];
      home.sessionPath = lib.mkBefore [
        (config.home.profileDirectory + "/bin")
        resources
      ];
      home.packages = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.bubblewrap;
      launchd.agents.codex-environment =
        lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && config.home.sessionVariables ? CODEX_HOME)
          {
            enable = true;
            config = {
              ProgramArguments = [
                "/bin/launchctl"
                "setenv"
                "CODEX_HOME"
                config.home.sessionVariables.CODEX_HOME
              ];
              RunAtLoad = true;
            };
          };

      programs.codex = {
        enableMcpIntegration = true;
        skills = lib.mapAttrs (name: _: ./skills + "/${name}") (
          lib.filterAttrs (
            name: type:
            type == "directory" && (builtins.readDir (./skills + "/${name}"))."SKILL.md" or null == "regular"
          ) (builtins.readDir ./skills)
        );
        context = ''
          For every code creation or modification, and for every code review,
          use the available managed skills' descriptions to identify applicable
          instructions. Read and apply those skills before starting implementation
          or review, and apply them again when reviewing the completed changes.
        '';
        # Install the CLI from ChatGPT; this option manages its settings.
        package = lib.mkDefault null;
        # Preserve application settings and project trust in a writable user file.
        mutableSettings = true;
        settings = {
          model = "gpt-6.1-terra";
          model_reasoning_effort = "ultra";
          plan_mode_reasoning_effort = "ultra";
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
    })
  ];
}
