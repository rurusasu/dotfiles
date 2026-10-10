# Package identities and provider declarations for terminal.
{ pkgs, ... }:
{
  # Unix installation and configuration belong to the Home Manager module.
  wezterm = {
    winget = "wez.wezterm";
    category = "terminal";
    support = {
      darwin.unsupported = "WezTerm is managed by Home Manager";
      linux.unsupported = "WezTerm is managed by Home Manager";
    };
  };

  aerospace = {
    pkg = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.aerospace else null;
    category = "terminal";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "aerospace";
        identity = {
          appName = "AeroSpace.app";
        };
      };
      linux.unsupported = "AeroSpace is only available on macOS";
      windows.unsupported = "AeroSpace is only available on macOS";
    };
  };

  autohotkey = {
    winget = "AutoHotkey.AutoHotkey";
    category = "terminal";
    support = {
      darwin = {
        unsupported = "AutoHotkey is only available on Windows";
      };
      linux = {
        unsupported = "AutoHotkey is only available on Windows";
      };
      windows = {
        provider = "winget";
        source = "winget";
        identity = "AutoHotkey.AutoHotkey";
      };
    };
  };

  zsh-patina = {
    pkg = pkgs.zsh-patina;
    category = "terminal";
    support.windows.unsupported = "No reviewed MSYS2/Cygwin package provider is selected";
  };
}
