#!/usr/bin/env bats

@test "chezmoi runs only the Windows WezTerm deployment script" {
    command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source_dir="$BATS_TEST_TMPDIR/source"
    cp -R "$REPO_ROOT/chezmoi" "$source_dir"
    script="$source_dir/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl"
    [[ -f "$script" ]]
    [[ "$(<"$script")" == *'.config/wezterm/wezterm.lua'* ]]
    [[ "$(<"$script")" != *'Windows Terminal'* ]]
    [[ "$(<"$script")" != *'LOCALAPPDATA'* ]]

    for os in linux darwin windows; do
        destination="$BATS_TEST_TMPDIR/$os/home"
        mkdir -p "$destination"
        chezmoi_args=(
            --config /dev/null --config-format toml
            --source "$source_dir" --destination "$destination"
            --cache "$BATS_TEST_TMPDIR/$os/cache"
            --persistent-state "$BATS_TEST_TMPDIR/$os/state.boltdb"
            --override-data "{\"chezmoi\":{\"os\":\"$os\",\"homeDir\":\"$destination\"}}"
        )
        run chezmoi "${chezmoi_args[@]}" managed --path-style relative
        [ "$status" -eq 0 ]
        run chezmoi "${chezmoi_args[@]}" managed --include scripts --path-style relative
        [ "$status" -eq 0 ]
        if [ "$os" = windows ]; then
            [ "$output" = ".chezmoiscripts/deploy/terminals/deploy.ps1" ]
        else
            [ -z "$output" ]
        fi
    done
}
