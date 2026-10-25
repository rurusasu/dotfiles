{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    wsl
    configuredChrome
    lib
    ;
  selectedChrome = lib.findFirst (
    package: (package.pname or "") == wsl.pkgs.google-chrome.pname
  ) null wsl.config.home.packages;
in
{
  testWslChromePackageUsesDeclaredLocaleAndLanguage = {
    expr = if selectedChrome == null then null else selectedChrome.postFixup;
    expected = (configuredChrome wsl).postFixup;
  };

  testWslChromeBuildsAnExplicitFcitxGtk3ModuleCache = {
    expr =
      let
        inherit (wsl) pkgs;
        markerStart = "__DOTFILES_GTK_CACHE_BEGIN__";
        markerEnd = "__DOTFILES_GTK_CACHE_END__";
        selected = import ../../../modules/browsers/chrome {
          pkgs = pkgs // {
            runCommand =
              name: attrs: script:
              markerStart
              + builtins.toJSON {
                inherit name script;
                nativeBuildInputs = map toString attrs.nativeBuildInputs;
                inherit (attrs) preferLocalBuild allowSubstitutes;
                disallowedReferences = map toString attrs.disallowedReferences;
              }
              + markerEnd;
          };
        };
        pieces = pkgs.lib.splitString markerStart selected.postFixup;
      in
      if builtins.length pieces == 2 then
        builtins.fromJSON (
          builtins.unsafeDiscardStringContext (
            builtins.head (pkgs.lib.splitString markerEnd (builtins.elemAt pieces 1))
          )
        )
      else
        null;
    expected = {
      name = "chrome-fcitx-gtk3-immodules.cache";
      nativeBuildInputs = [ (toString wsl.pkgs.gtk3) ];
      preferLocalBuild = true;
      allowSubstitutes = false;
      disallowedReferences = [ (toString (wsl.pkgs.lib.getDev wsl.pkgs.gtk3)) ];
      script = ''
        gtk-query-immodules-3.0 "${wsl.pkgs.fcitx5-gtk}/lib/gtk-3.0/3.0.0/immodules/im-fcitx5.so" > "$out"
      '';
    };
  };
}
