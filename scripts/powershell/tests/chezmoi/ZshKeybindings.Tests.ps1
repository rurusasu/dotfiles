#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
}

Describe 'zsh keybindings' {
    It 'should bind delete keys explicitly for terminal compatibility' {
        $homeManagerZsh = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/common.nix") -Raw
        $zshHelper = Get-Content -LiteralPath (Join-Path $script:repoRoot "chezmoi/dot_config/shell/gh-token-switch.sh") -Raw

        $homeManagerZsh | Should -Match 'gh-token-switch\.sh'
        $zshHelper | Should -Match '\$\{ZSH_VERSION:-\}'
        $zshHelper | Should -Match 'bindkey ''\^\?'' backward-delete-char'
        $zshHelper | Should -Match 'bindkey ''\^H'' backward-delete-char'
        $zshHelper | Should -Match 'terminfo\[kdch1\].*delete-char'
        $zshHelper | Should -Match 'bindkey ''\^\[\[3~'' delete-char'
    }
}
