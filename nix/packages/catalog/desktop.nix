# Package identities and provider declarations for desktop.
{
  pkgs,
  lib,
  selectDarwinPackage,
  darwinProviderCandidate,
  darwinDiscordPackage,
  ...
}:
{
  glazewm = {
    winget = "glzr-io.glazewm";
    category = "desktop";
    support = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "glzr-io.glazewm";
      };
      darwin.unsupported = "AeroSpace owns the macOS desktop session";
      linux.unsupported = "Hyprland owns native NixOS; WSL uses the Windows desktop backend";
    };
  };

  chatgpt = {
    pkg = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.chatgpt else pkgs.callPackage ../chatgpt { };
    category = "desktop";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "chatgpt";
        identity = {
          appName = "ChatGPT.app";
        };
      };
      linux = {
        provider = "nix";
        source = "dotfiles";
        identity = "chatgpt";
        nixAttr = "chatgpt";
      };
      windows = {
        unsupported = "The Windows Store app is intentionally excluded from this package catalog";
      };
    };
  };

  steam = {
    category = "desktop";
    support = {
      darwin = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "steam";
        cask = "steam";
      };
      linux = {
        unsupported = "Steam is managed through the native platform package manager";
      };
      windows = {
        unsupported = "Steam is managed through the Windows package manifest";
      };
    };
  };

  discord = {
    pkg = if pkgs.stdenv.hostPlatform.isDarwin then darwinDiscordPackage else pkgs.discord;
    winget = "Discord.Discord";
    category = "desktop";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "discord";
        identity = {
          appName = "Discord.app";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "discord";
        nixAttr = "discord";
      };
    };
  };

  _1password-gui = {
    pkg = pkgs._1password-gui;
    winget = "AgileBits.1Password";
    category = "desktop";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "_1password-gui";
        identity = {
          appName = "1Password.app";
        };
      };
    };
  };

  arc-browser = {
    winget = "TheBrowserCompany.Arc";
    category = "desktop";
    support = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "TheBrowserCompany.Arc";
      };
      darwin = {
        unsupported = "Use Dia instead of Arc on macOS";
      };
      linux = {
        unsupported = "Vendor does not publish a Linux build";
      };
    };
  };

  dia-browser = {
    pkg =
      if pkgs.stdenv.hostPlatform.isDarwin then
        selectDarwinPackage "dia-browser" (pkgs.callPackage ../dia-browser { })
      else
        null;
    category = "desktop";
    support = {
      windows = {
        unsupported = "Vendor currently ships Dia for macOS only";
      };
      darwin = {
        provider = "nix";
        inherit ((darwinProviderCandidate "dia-browser")) source;
        identity = {
          appName = "Dia.app";
        };
      }
      // lib.optionalAttrs ((darwinProviderCandidate "dia-browser").nixAttr != null) {
        inherit ((darwinProviderCandidate "dia-browser")) nixAttr;
      };
      linux = {
        unsupported = "Vendor currently ships Dia for macOS only";
      };
    };
  };

  google-chrome = {
    pkg = pkgs.google-chrome;
    winget = "Google.Chrome";
    category = "desktop";
    installFeature = "WithHermes";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "google-chrome";
        identity = {
          appName = "Google Chrome.app";
        };
      };
    };
  };

  orca-editor = {
    pkg =
      if pkgs.stdenv.hostPlatform.isDarwin then
        selectDarwinPackage "orca-editor" (pkgs.callPackage ../orca-editor { })
      else
        null;
    winget = "StablyAI.Orca";
    category = "desktop";
    support = {
      darwin = {
        provider = "nix";
        inherit ((darwinProviderCandidate "orca-editor")) source;
        identity = {
          appName = "Orca.app";
        };
      }
      // lib.optionalAttrs ((darwinProviderCandidate "orca-editor").nixAttr != null) {
        inherit ((darwinProviderCandidate "orca-editor")) nixAttr;
      };
      linux = {
        unsupported = "No reviewed Linux desktop package provider is selected";
      };
    };
  };

  raycast = {
    pkg = pkgs.raycast;
    category = "desktop";
    support = {
      windows = {
        unsupported = "Managed only on macOS in this dotfiles profile";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "raycast";
        identity = {
          appName = "Raycast.app";
        };
      };
      linux = {
        unsupported = "Vendor does not publish a Linux build";
      };
    };
  };
}
