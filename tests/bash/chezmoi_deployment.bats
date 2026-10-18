#!/usr/bin/env bats

@test "chezmoi selects the Windows terminal, font, and keyboard deployment scripts" {
    command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    fixture_root="$BATS_TEST_TMPDIR/source"
    source_dir="$fixture_root/chezmoi"
    mkdir -p "$fixture_root/nix/home/keybindings" "$fixture_root/scripts/powershell"
    cp -R "$REPO_ROOT/chezmoi" "$source_dir"
    cp "$REPO_ROOT/nix/home/keybindings/generated.json" "$fixture_root/nix/home/keybindings/generated.json"
    cp "$REPO_ROOT/scripts/powershell/Sync-PowerToysKeyboard.ps1" "$fixture_root/scripts/powershell/Sync-PowerToysKeyboard.ps1"
    cp "$REPO_ROOT/scripts/powershell/Invoke-DesktopAction.ps1" "$fixture_root/scripts/powershell/Invoke-DesktopAction.ps1"

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
            [ "$output" = $'.chezmoiscripts/deploy/keybindings/sync_powertoys_keyboard.ps1\n.chezmoiscripts/deploy/keybindings/sync_wsl_keybindings.ps1\n.chezmoiscripts/deploy/terminals/deploy.ps1\n.chezmoiscripts/deploy/terminals/install_udev_gothic_nf.ps1' ]
        else
            [ -z "$output" ]
        fi
    done
}
