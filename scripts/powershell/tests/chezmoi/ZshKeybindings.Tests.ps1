#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
}

Describe 'zsh keybindings' {
    It 'should bind delete keys explicitly for terminal compatibility' {
        $homeManagerZsh = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/shells/zsh/bindings.zsh") -Raw
        $zshHelper = Get-Content -LiteralPath (Join-Path $script:repoRoot "chezmoi/dot_config/shell/gh-token-switch.sh") -Raw

        $zshHelper | Should -Not -Match 'bindkey|zmodload|ZSH_VERSION'
        $homeManagerZsh | Should -Match 'bindkey ''\^\?'' backward-delete-char'
        $homeManagerZsh | Should -Match 'bindkey ''\^H'' backward-delete-char'
        $homeManagerZsh | Should -Match 'bindkey.*terminfo\[kdch1\].*delete-char'
        $homeManagerZsh | Should -Match 'bindkey ''\^\[\[3~'' delete-char'
    }
}
