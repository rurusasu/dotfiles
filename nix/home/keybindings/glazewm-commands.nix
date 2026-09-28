# Windows user application choices; all helpers are deployed by chezmoi.
{ lib }:
let
  actions = [
    "terminal"
    "browser"
    "files"
    "notes"
    "ai"
    "passwords"
    "launcher"
    "help"
    "capture"
    "calculator"
    "activity"
    "lock"
    "clipboard"
    "emoji"
    "audio"
    "bluetooth"
    "display"
    "network"
    "power"
  ];
  run =
    action:
    ''powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "& (Join-Path $env:USERPROFILE '.glzr/glazewm/actions.ps1') -Action '${action}'"'';
in
builtins.listToAttrs (map (action: lib.nameValuePair action (run action)) actions)
