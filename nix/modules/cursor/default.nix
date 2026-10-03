{ config, pkgs, ... }:
let
  # 見た目などの既存設定を保持し、LSP 設定だけを Nix 側で追加する。
  inherit (builtins.fromJSON (builtins.readFile ../../../chezmoi/.chezmoidata/appearance.json))
    appearance
    ;
  baseline = builtins.fromJSON (
    builtins.replaceStrings
      [
        "{{ .appearance.font_size }}"
        "\"{{ .appearance.font_family }}\""
        "\"{{ .appearance.theme }}\""
        "\"{{ .appearance.icon_theme }}\""
      ]
      (map builtins.toJSON [
        appearance.font_size
        appearance.font_family
        appearance.theme
        appearance.icon_theme
      ])
      (builtins.readFile ../../../chezmoi/editors/cursor/settings.json)
  );
  settings = import ./lsp.nix {
    inherit (config.home) homeDirectory;
    isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  };
in
{
  programs.cursor = {
    enable = true;
    # GUI 本体の既存の導入方法を変更せず、設定だけを管理する。
    package = null;
    profiles.default = {
      userSettings = baseline // settings;
      # 既存のキー設定をそのまま配布し、chezmoi との二重管理を避ける。
      keybindings = ../../../chezmoi/editors/cursor/keybindings.json;
      # 手動設定を保持しながら、宣言した設定を Home Manager が反映する。
      mutableUserSettings = true;
      enableUpdateCheck = null;
      enableExtensionUpdateCheck = null;
    };
  };
}
