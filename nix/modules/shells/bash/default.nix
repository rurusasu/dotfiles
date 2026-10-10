{ lib, ... }:
{
  # Bash configuration is generated together with terminal shell integrations.
  programs.bash = {
    enable = true;
    initExtra = lib.mkBefore (builtins.readFile ./bashrc);
    profileExtra = ''
      # Set PATH so it includes user's private bin if it exists
      if [ -d "$HOME/bin" ]; then
        PATH="$HOME/bin:$PATH"
      fi
      if [ -d "$HOME/.local/bin" ]; then
        PATH="$HOME/.local/bin:$PATH"
      fi

      # User-local npm globals
      if [ -d "$HOME/.local/npm/bin" ]; then
        case ":$PATH:" in
          *":$HOME/.local/npm/bin:"*) ;;
          *) PATH="$HOME/.local/npm/bin:$PATH" ;;
        esac
      fi

      # bun global binaries
      if [ -d "$HOME/.bun/bin" ]; then
        PATH="$HOME/.bun/bin:$PATH"
      fi

      export PATH
    '';
  };
}
