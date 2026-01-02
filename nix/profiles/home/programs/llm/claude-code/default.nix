{ pkgs, ... }:
{
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    settings = {
      permissions = {
        allow = [
          "Bash(git remote add:*)"
          "Bash(git fetch:*)"
          "Bash(ssh:*)"
          "Bash(git remote set-url:*)"
          "Bash(sudo apt update:*)"
          "Bash(sudo apt install:*)"
          "Bash(mkdir:*)"
          "Bash(chmod:*)"
          "Bash(tree:*)"
          "WebFetch(domain:zenn.dev)"
          "Bash(stow:*)"
          "Bash(sudo chown:*)"
          "Bash(ln:*)"
          "Bash(bash:*)"
          "Bash(cat:*)"
          "Bash(git add:*)"
          "Bash(git commit:*)"
          "WebSearch"
          "Bash(nvim:*)"
          "Bash(code-insiders:*)"
          "Bash(test:*)"
          "Bash(echo:*)"
          "WebFetch(domain:marketplace.visualstudio.com)"
          "Bash(sudo add-apt-repository:*)"
          "Bash(curl:*)"
          "Bash(wget:*)"
          "Bash(command -v:*)"
          "Bash(rm:*)"
          "Bash(git config:*)"
          "Bash(xargs:*)"
          "Bash(ssh-add:*)"
          "Bash(git push:*)"
          "WebFetch(domain:github.com)"
          "Bash(mv:*)"
          "WebFetch(domain:devenv.sh)"
          "Bash(pwsh:*)"
          "Bash(wsl --shutdown)"
          "Bash(wsl -d NixOS -- zsh:*)"
          "Bash(wsl -d NixOS -- bash -c:*)"
          "Bash(git mv:*)"
          "Bash(git rm:*)"
          "Bash(readlink:*)"
        ];
        deny = [];
      };
    };
  };
}
