# Package identities and provider declarations for terminal.
{ pkgs, ... }:
{
  ghostty = {
    pkg = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    category = "terminal";
    support = {
      windows.unsupported = "Ghostty is configured only for macOS and Linux";
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "ghostty-bin";
        identity = {
          homepage = "https://ghostty.org/";
          appName = "Ghostty.app";
          bundleId = "com.mitchellh.ghostty";
          executable = "ghostty";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "ghostty";
        identity = "ghostty";
      };
    };
  };

  wezterm = {
    pkg = pkgs.wezterm;
    winget = "wez.wezterm";
    category = "terminal";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "wezterm";
        identity = {
          homepage = "https://wezterm.org/";
          appName = "WezTerm.app";
          bundleId = "com.github.wez.wezterm";
          executable = "wezterm-gui";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "wezterm";
        nixAttr = "wezterm";
      };
    };
    legacyDarwin = {
      provider = "homebrew-cask";
      name = "wezterm@nightly";
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
          homepage = "https://github.com/nikitabobko/AeroSpace";
          appName = "AeroSpace.app";
          bundleId = "bobko.aerospace";
          executable = "aerospace";
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

  tmux = {
    pkg = pkgs.tmux;
    winget = null;
    category = "terminal";
  };

  starship = {
    pkg = pkgs.starship;
    winget = "Starship.Starship";
    category = "terminal";
  };

  hermes-desktop = {
    winget = null;
    category = "terminal";
    installFeature = "WithHermes";
    support = {
      darwin = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "hermes-desktop";
        cask = "hermes-desktop";
      };
      linux = {
        unsupported = "Hermes Desktop is provisioned by the native macOS profile";
      };
      windows = {
        unsupported = "Hermes Desktop is provisioned by the native macOS profile";
      };
    };
  };
}
