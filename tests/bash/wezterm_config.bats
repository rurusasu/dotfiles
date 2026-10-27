#!/usr/bin/env bats
setup() {
    command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required"
    REPO_ROOT="${WEZTERM_TEST_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
    mkdir -p "$BATS_TEST_TMPDIR/home"
    export HOME="$BATS_TEST_TMPDIR/home"
}
@test "chezmoi deploy template contains only the Windows WezTerm target" {
    for os in linux darwin windows; do
        rendered=$(chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
            --destination "$HOME" --cache "$BATS_TEST_TMPDIR/cache" --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
            --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" execute-template \
            --file "$REPO_ROOT/chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl")
        if [[ $os == windows ]]; then
            [[ $rendered == *'local wezterm = require("wezterm")'* ]]
            [[ $rendered == *'.config/wezterm/wezterm.lua'* ]]
            [[ $rendered != *'Windows Terminal'* ]]
        else
            [ -z "$rendered" ]
        fi
    done
}
@test "chezmoi manages Windows user configuration and excludes Unix homes" {
    for os in linux darwin windows; do
        managed=$(chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
            --destination "$HOME" --cache "$BATS_TEST_TMPDIR/cache" --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
            --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" managed --include files --path-style relative)
        if [[ $os == windows ]]; then
            [ "$managed" = $'.config/dotfiles/wslg-fontconfig.conf\n.config/git/config\n.wslgconfig\nAppData/Local/superfile/config.toml\nDocuments/PowerShell/Microsoft.PowerShell_profile.ps1' ]
            scripts=$(chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
                --destination "$HOME" --cache "$BATS_TEST_TMPDIR/scripts-cache" --persistent-state "$BATS_TEST_TMPDIR/scripts-state.boltdb" \
                --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" managed --include scripts --path-style relative)
            [ "$scripts" = $'.chezmoiscripts/deploy/keybindings/sync_wsl_keybindings.ps1\n.chezmoiscripts/deploy/terminals/deploy.ps1\n.chezmoiscripts/deploy/terminals/install_udev_gothic_nf.ps1' ]
        else
            [ -z "$managed" ]
        fi
    done
}
