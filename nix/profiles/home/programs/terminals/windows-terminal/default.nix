{ pkgs, lib, config, ... }:
let
  # Windows Terminal settings as Nix expression
  settings = {
    "$help" = "https://aka.ms/terminal-documentation";
    "$schema" = "https://aka.ms/terminal-profiles-schema";

    # Actions
    actions = [
      {
        command = { action = "copy"; singleLine = false; };
        id = "User.copy.644BA8F2";
      }
      { command = "paste"; id = "User.paste"; }
      {
        command = { action = "splitPane"; split = "horizontal"; splitMode = "duplicate"; };
        id = "User.splitPane.horizontal";
      }
      {
        command = { action = "splitPane"; split = "vertical"; splitMode = "duplicate"; };
        id = "User.splitPane.vertical";
      }
      { command = "find"; id = "User.find"; }
      { command = "closePane"; id = "User.closePane"; }
      { command = "nextTab"; id = "User.nextTab"; }
      { command = "prevTab"; id = "User.prevTab"; }
      # Unbind Alt+C and Alt+Z for fzf
      { command = "unbound"; keys = "alt+c"; }
      { command = "unbound"; keys = "alt+z"; }
    ];

    # Copy settings
    copyFormatting = "none";
    copyOnSelect = false;

    # Default profile (PowerShell Core)
    defaultProfile = "{574e775e-4f2a-5b96-ac1e-a2962a402336}";

    # Global settings
    language = "ja";
    alwaysShowNotificationIcon = true;
    useAcrylicInTabRow = true;
    showTabsFullscreen = true;

    # Keybindings
    keybindings = [
      { id = "User.copy.644BA8F2"; keys = "ctrl+c"; }
      { id = "User.paste"; keys = "ctrl+v"; }
      { id = "User.find"; keys = "ctrl+shift+f"; }
      { id = "User.splitPane.horizontal"; keys = "ctrl+shift+h"; }
      { id = "User.splitPane.vertical"; keys = "ctrl+shift+v"; }
      { id = "User.closePane"; keys = "ctrl+shift+x"; }
      { id = "User.nextTab"; keys = "ctrl+tab"; }
      { id = "User.prevTab"; keys = "ctrl+shift+tab"; }
    ];

    # New tab menu
    newTabMenu = [{ type = "remainingProfiles"; }];

    # Profiles
    profiles = {
      # Default settings for all profiles
      defaults = {
        font = {
          face = "Consolas";
          size = 12;
        };
        useAcrylic = true;
        opacity = 85;
        colorScheme = "One Half Dark";
        cursorShape = "bar";
        padding = "8, 8, 8, 8";
      };
      list = [
        {
          commandline = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
          guid = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}";
          hidden = false;
          name = "Windows PowerShell";
        }
        {
          commandline = "%SystemRoot%\\System32\\cmd.exe";
          guid = "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}";
          hidden = false;
          name = "コマンド プロンプト";
        }
        {
          guid = "{b453ae62-4e3d-5e58-b989-0a998ec441b8}";
          hidden = true;
          name = "Azure Cloud Shell";
          source = "Windows.Terminal.Azure";
        }
        {
          elevate = true;
          guid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}";
          hidden = false;
          name = "PowerShell";
          source = "Windows.Terminal.PowershellCore";
          backgroundImage = "desktopWallpaper";
          backgroundImageOpacity = 0.25;
          backgroundImageStretchMode = "uniformToFill";
          colorScheme = "CGA";
          opacity = 25;
        }
        {
          guid = "{b6523b27-da58-57e8-ae53-e1f73380400d}";
          hidden = false;
          name = "Ubuntu-24.04";
          source = "Microsoft.WSL";
        }
        {
          guid = "{39d64555-b17f-5912-8d8e-2a01e69d9673}";
          hidden = true;
          name = "Ubuntu";
          source = "Microsoft.WSL";
        }
        {
          guid = "{55bf1f9a-7b1e-542e-877c-89bbdeae0402}";
          hidden = true;
          name = "Developer Command Prompt for VS 21";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{5dd0a95e-998e-503b-874d-b2d83f552911}";
          hidden = true;
          name = "Developer PowerShell for VS 21";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}";
          hidden = false;
          name = "Git Bash";
          source = "Git";
        }
        {
          guid = "{b5fdcf37-ec3e-5a08-8f59-dee726688d80}";
          hidden = true;
          name = "Developer Command Prompt for VS 2022";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{375eb4b6-c4c0-5648-8a38-0d8f88c7b880}";
          hidden = true;
          name = "Developer PowerShell for VS 2022";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{2f733b2d-cc70-54fa-be59-88dd0e7eb1f4}";
          hidden = true;
          name = "Developer Command Prompt for VS 18";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{551d7d6d-9712-5b38-817d-de5397c961c1}";
          hidden = true;
          name = "Developer PowerShell for VS 18";
          source = "Windows.Terminal.VisualStudio";
        }
        {
          guid = "{bc78590e-5f0e-5af3-9cfc-8683e86326e6}";
          hidden = true;
          name = "Ubuntu";
          source = "Microsoft.WSL";
        }
        {
          guid = "{265f58cc-343d-58ab-af9f-53bd9c7e769f}";
          hidden = false;
          name = "NixOS";
          source = "Microsoft.WSL";
        }
      ];
    };

    schemes = [ ];
    themes = [ ];
  };

  # Generate JSON file
  settingsJson = pkgs.writeText "windows-terminal-settings.json"
    (builtins.toJSON settings);
in
{
  # Export the generated settings path for scripts to use
  home.file.".config/windows-terminal/settings.json".source = settingsJson;

  # Also create an activation script hint
  home.file.".config/windows-terminal/README.md".text = ''
    # Windows Terminal Settings

    This directory contains Windows Terminal settings generated by Nix.

    To apply to Windows Terminal, run from Windows PowerShell (as Administrator):
    ```powershell
    .\windows\scripts\apply-settings.ps1
    ```

    Or manually create a symlink:
    ```powershell
    New-Item -ItemType SymbolicLink `
      -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" `
      -Target "\\wsl$\NixOS\home\<user>\.config\windows-terminal\settings.json"
    ```
  '';
}
