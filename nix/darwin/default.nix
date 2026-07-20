{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  assertions = [
    {
      assertion = user != "";
      message = "DOTFILES_USER is required";
    }
    {
      assertion = home != "";
      message = "DOTFILES_HOME is required";
    }
  ];

  system = {
    primaryUser = user;
    stateVersion = 6;
    tools.darwin-uninstaller.enable = false;
    activationScripts.raycastHotkey.text = ''
      # Configure Raycast as the launcher hotkey while preserving the rest of
      # macOS's AppleSymbolicHotKeys dictionary.
      uid="$(id -u -- ${lib.escapeShellArg user})"
      symbolicHotKeysPlist=${lib.escapeShellArg "${home}/Library/Preferences/com.apple.symbolichotkeys.plist"}
      runAsUser() {
        launchctl asuser "$uid" sudo --user=${lib.escapeShellArg user} -- "$@"
      }

      if ! runAsUser /bin/test -s "$symbolicHotKeysPlist"; then
        runAsUser /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict
      fi
      runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys dict" "$symbolicHotKeysPlist" 2>/dev/null || true

      disableSymbolicHotKey() {
        key="$1"
        parameter0="$2"
        parameter1="$3"
        parameter2="$4"

        runAsUser /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:$key" "$symbolicHotKeysPlist" 2>/dev/null || true
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key dict" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:enabled bool false" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value dict" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value:parameters array" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value:parameters:0 integer $parameter0" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value:parameters:1 integer $parameter1" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value:parameters:2 integer $parameter2" "$symbolicHotKeysPlist"
        runAsUser /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$key:value:type string standard" "$symbolicHotKeysPlist"
      }

      disableSymbolicHotKey 60 32 49 1048576
      disableSymbolicHotKey 61 32 49 1572864
      disableSymbolicHotKey 64 65535 49 1048576
      disableSymbolicHotKey 65 65535 49 1572864
      disableSymbolicHotKey 156 65535 49 393216
      runAsUser /usr/bin/plutil -convert binary1 "$symbolicHotKeysPlist"
      runAsUser /usr/bin/defaults write com.raycast.macos raycastGlobalHotkey -string Command-49
      runAsUser /usr/bin/defaults write com.raycast.macos onboarding_setupHotkey -bool true
      runAsUser /usr/bin/defaults write com.raycast.macos mainWindow_isMonitoringGlobalHotkeys -bool true
      runAsUser /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
      runAsUser /usr/bin/killall cfprefsd 2>/dev/null || true
      runAsUser /usr/bin/killall SystemUIServer 2>/dev/null || true
      runAsUser /usr/bin/open -gj -a Raycast 2>/dev/null || true
    '';
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # nix-darwin's generated documentation currently passes a removed
  # nixos-render-docs flag. Omit the optional manual artifacts and the
  # uninstaller's nested default system, which otherwise rebuilds them.
  documentation.enable = false;

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    inherit user;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    casks = sets.darwinCasks;
    greedyCasks = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "none";
    };
  };

  users.users.${user}.home = home;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} =
      { ... }:
      {
        imports = [ ../home/common.nix ];

        programs.zsh.shellAliases = {
          nrs = "~/.dotfiles/install.sh";
        };
      };
    extraSpecialArgs = { inherit inputs; };
  };
}
