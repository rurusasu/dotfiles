{
  config,
  lib,
  pkgs,
  ...
}:
let
  codexHome = "${config.home.homeDirectory}/.codex";
  rules = lib.mapAttrs' (
    name: _: lib.nameValuePair (lib.removeSuffix ".rules" name) (./rules + "/${name}")
  ) (builtins.readDir ./rules);
  agents = {
    fast_worker = "Fast scoped implementation agent.";
    python_coding = "Python implementation-only agent (no test execution).";
  };
  scripts = {
    "command_permission_policy.py" = "Checking command policy";
    "deny_protected_branch_commit.py" = "Checking protected branch policy";
  };
  enabledPlugins = [
    "slack"
    "github"
    "hugging-face"
    "codex-security"
    "gmail"
    "google-drive"
    "openai-developers"
    "google-calendar"
  ];
  managedFiles = [
    ".codex/AGENTS.override.md"
    ".codex/hooks.json"
  ]
  ++ map (name: ".codex/rules/${name}.rules") (builtins.attrNames rules);
in
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.chatgpt ];

  programs.codex = {
    enable = true;
    # The ChatGPT app supplies the CLI; Home Manager owns configuration only.
    package = null;
    # Preserve application settings and project trust in a writable user file.
    mutableSettings = true;
    contextOverride = ./AGENTS.override.md;
    inherit rules;
    hooks.PreToolUse = [
      {
        matcher = "^Bash$";
        hooks = lib.mapAttrsToList (name: statusMessage: {
          type = "command";
          command = "${pkgs.python3}/bin/python3 ${lib.escapeShellArg "${codexHome}/hooks/${name}"}";
          timeout = 30;
          inherit statusMessage;
        }) scripts;
      }
    ];
    settings = {
      model = "gpt-6-luna";
      model_reasoning_effort = "high";
      plan_mode_reasoning_effort = "high";
      model_reasoning_summary = "auto";
      model_verbosity = "low";
      approval_policy = "never";
      default_permissions = ":danger-full-access";
      web_search = "live";
      shell_environment_policy = {
        "inherit" = "all";
        exclude = [
          "*KEY*"
          "*TOKEN*"
          "*SECRET*"
          "*PASSWORD*"
          "*CREDENTIAL*"
        ];
        set.TERM = "xterm-256color";
      };
      features = {
        hooks = true;
        unified_exec = true;
        apps = true;
      };
      tui.keymap.editor.insert_newline = [
        "shift-enter"
        "ctrl-enter"
        "ctrl-j"
      ];
      tools.view_image = true;
      skills.config =
        map
          (name: {
            inherit name;
            path = "~/.codex/skills/${name}";
            enabled = true;
          })
          [
            "python-clean-architecture"
            "python-docstring"
          ];
      agents = {
        max_threads = 12;
        max_depth = 2;
        job_max_runtime_seconds = 3600;
      }
      // lib.mapAttrs (name: description: {
        inherit description;
        config_file = "${codexHome}/agents/${name}.toml";
      }) agents;
      mcp_servers.MCP_DOCKER = {
        command = "docker";
        args = [
          "mcp"
          "gateway"
          "run"
          "--profile"
          "dotfiles"
        ];
        startup_timeout_sec = 30;
      };
      plugins =
        lib.genAttrs (map (name: "${name}@openai-curated") enabledPlugins) (_: {
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

  # Take over previously chezmoi-managed files, without touching auth or sessions.
  home.file =
    lib.genAttrs managedFiles (_: {
      force = true;
    })
    // lib.mapAttrs' (
      name: _:
      lib.nameValuePair ".codex/agents/${name}.toml" {
        source = ./agents + "/${name}.toml";
        force = true;
      }
    ) agents
    // lib.mapAttrs' (
      name: _:
      lib.nameValuePair ".codex/hooks/${name}" {
        source = ./hooks + "/${name}";
        force = true;
      }
    ) scripts;
}
