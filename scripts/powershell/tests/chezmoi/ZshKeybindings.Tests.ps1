#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
}

Describe 'zsh keybindings' {
    It 'should bind delete keys explicitly for terminal compatibility' {
        $homeManagerZsh = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/modules/shells/zsh/bindings.zsh") -Raw
        $zshFunctions = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/modules/shells/zsh/functions.zsh") -Raw
        $zshHelper = Get-Content -LiteralPath (Join-Path $script:repoRoot "chezmoi/dot_config/shell/gh-token-switch.sh") -Raw

        $zshFunctions | Should -Match 'gh-token-switch\.sh'
        $zshHelper | Should -Not -Match 'bindkey|zmodload|ZSH_VERSION'
        $homeManagerZsh | Should -Match 'bindkey ''\^\?'' backward-delete-char'
        $homeManagerZsh | Should -Match 'bindkey ''\^H'' backward-delete-char'
        $homeManagerZsh | Should -Match 'bindkey.*terminfo\[kdch1\].*delete-char'
        $homeManagerZsh | Should -Match 'bindkey ''\^\[\[3~'' delete-char'
    }
}
