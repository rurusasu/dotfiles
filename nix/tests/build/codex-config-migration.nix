{ inputs, pkgs }:
pkgs.runCommand "codex-config-migration-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.jaq
    ];
    activation = pkgs.writeText "codex-agent-migration-activation" ''
      source ${inputs.home-manager}/lib/bash/home-manager.sh
      ${((import ../../modules/ai_agents/chatgpt).homeManager {
        inherit pkgs;
        lib = import "${inputs.home-manager}/modules/lib/stdlib-extended.nix" pkgs.lib;
        config = {
          home.homeDirectory = "@TEST HOME@";
          home.preferXdgDirectories = true;
          xdg.configHome = "@TEST HOME@/.config";
        };
      }).home.activation.codexPruneManagedAgents.data
      }
    '';
  }
  ''
    export NO_COLOR=1
    test_home="$TMPDIR/home with spaces"
    mkdir -p "$test_home/.config/codex"
    ln -s .config/codex "$test_home/.codex"
    config="$test_home/.config/codex/config.toml"
    substitute "$activation" "$TMPDIR/activate" --replace-fail '@TEST HOME@' "$test_home"
    migrate() { bash -e "$TMPDIR/activate"; }

    # These old absolute paths survive the directory move into XDG configHome.
    cat > "$config" <<EOF
    model = "user-model"
    api_key = "test-secret-to-preserve"
    [agents]
    max_threads = 4
    [agents.fast_worker]
    config_file = "$test_home/.codex/agents/fast_worker.toml"
    description = "previous managed role"
    [agents.python_coding]
    config_file = "$test_home/.codex/agents/python_coding.toml"
    [agents.reviewer]
    config_file = "/custom/reviewer.toml"
    [features]
    hooks = true
    [projects."/work/project"]
    trust_level = "trusted"
    EOF
    mv "$config" "$test_home/actual.toml"
    ln -s "$test_home/actual.toml" "$config"
    chmod 0640 "$config"
    migrate
    test -L "$config"
    test "$(stat -Lc %a "$config")" = 640
    jaq -e --from toml '
      . == {
        model: "user-model",
        api_key: "test-secret-to-preserve",
        agents: {max_threads: 4, reviewer: {config_file: "/custom/reviewer.toml"}},
        features: {hooks: true},
        projects: {"/work/project": {trust_level: "trusted"}}
      }
    ' "$config" > /dev/null
    jaq --from toml '.' "$config" > "$TMPDIR/once.json"
    migrate
    jaq --from toml '.' "$config" > "$TMPDIR/twice.json"
    cmp "$TMPDIR/once.json" "$TMPDIR/twice.json"

    # Same role names with user-chosen paths must survive independently.
    cat > "$config" <<'EOF'
    [agents.fast_worker]
    config_file = "/custom/fast_worker.toml"
    [agents.python_coding]
    config_file = "~/.codex/agents/python_coding.toml"
    EOF
    migrate
    jaq -e --from toml '
      . == {agents: {
        fast_worker: {config_file: "/custom/fast_worker.toml"},
        python_coding: {config_file: "~/.codex/agents/python_coding.toml"}
      }}
    ' "$config" > /dev/null

    cat > "$config" <<EOF
    [agents.fast_worker]
    config_file = "$test_home/.codex/agents/fast_worker.toml"
    [agents.python_coding]
    config_file = "/custom/python_coding.toml"
    EOF
    cp "$config" "$TMPDIR/before-dry-run.toml"
    DRY_RUN=1 migrate
    cmp "$config" "$TMPDIR/before-dry-run.toml"
    migrate
    jaq -e --from toml '
      . == {agents: {python_coding: {config_file: "/custom/python_coding.toml"}}}
    ' "$config" > /dev/null

    printf '[agents.fast_worker\nconfig_file = "broken"\n' > "$config"
    cp "$config" "$TMPDIR/malformed.toml"
    if migrate > "$TMPDIR/error" 2>&1; then
      echo 'migration unexpectedly accepted malformed TOML' >&2
      exit 1
    fi
    cmp "$config" "$TMPDIR/malformed.toml"
    touch "$out"
  ''
