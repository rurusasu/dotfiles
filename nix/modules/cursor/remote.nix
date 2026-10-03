{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Windows の Cursor から接続した WSL の Remote 設定は別の場所に置かれる。
  settings = import ./lsp.nix {
    inherit (config.home) homeDirectory;
    isDarwin = false;
  };
  declaredSettings = (pkgs.formats.json { }).generate "cursor-remote-lsp-settings" settings;
  json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;
in
{
  # 既存の非 LSP 設定を保持してマージする。壊れた JSON は上書きしない。
  home.activation.cursorRemoteSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [[ -n "''${DRY_RUN:-}" ]]; then
      echo "Would merge Cursor Remote LSP settings"
    else
      (
        set -euo pipefail
        settings_file="$HOME/.cursor-server/data/Machine/settings.json"
        ${lib.getExe' pkgs.coreutils "mkdir"} -p "$(${lib.getExe' pkgs.coreutils "dirname"} "$settings_file")"
        existing=$(${lib.getExe' pkgs.coreutils "mktemp"} "$settings_file.input.XXXXXX")
        candidate=$(${lib.getExe' pkgs.coreutils "mktemp"} "$settings_file.new.XXXXXX")
        trap '${lib.getExe' pkgs.coreutils "rm"} -f "$existing" "$candidate"' EXIT
        if [[ -e "$settings_file" ]]; then
          ${lib.getExe json5} --as-json "$settings_file" > "$existing"
        else
          echo '{}' > "$existing"
        fi
        ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$existing" ${declaredSettings} > "$candidate"
        if [[ -f "$settings_file" ]]; then
          ${lib.getExe' pkgs.coreutils "chmod"} --reference="$settings_file" "$candidate"
        fi
        ${lib.getExe' pkgs.coreutils "mv"} "$candidate" "$settings_file"
      )
    fi
  '';
}
