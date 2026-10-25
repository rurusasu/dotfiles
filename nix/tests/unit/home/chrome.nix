{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    wsl
    configuredChrome
    ;
  selectedChrome = homeConfigurations.lib.findFirst (
    package: (package.pname or "") == wsl.pkgs.google-chrome.pname
  ) null wsl.config.home.packages;
  immodulesCache = (configuredChrome wsl).gtk3ImmodulesCache;
in
{
  testWslChromePackageUsesDeclaredLocaleAndLanguage = {
    expr = if selectedChrome == null then null else selectedChrome.postFixup;
    expected = (configuredChrome wsl).postFixup;
  };

  testWslChromeBuildsAnExplicitFcitxGtk3ModuleCache = {
    expr = {
      inherit (immodulesCache) name preferLocalBuild allowSubstitutes;
      nativeBuildInputs = map toString immodulesCache.nativeBuildInputs;
      disallowedReferences = map toString immodulesCache.disallowedReferences;
      script = immodulesCache.buildCommand;
    };
    expected = {
      name = "chrome-fcitx-gtk3-immodules.cache";
      nativeBuildInputs = map toString [
        (wsl.pkgs.lib.getDev wsl.pkgs.gtk3)
        wsl.pkgs.pkg-config
      ];
      preferLocalBuild = true;
      allowSubstitutes = false;
      disallowedReferences = [ (toString (wsl.pkgs.lib.getDev wsl.pkgs.gtk3)) ];
      script = ''
        gtk_binary_version="$(pkg-config --variable=gtk_binary_version gtk+-3.0)"
        gtk-query-immodules-3.0 "${wsl.pkgs.fcitx5-gtk}/lib/gtk-3.0/$gtk_binary_version/immodules/im-fcitx5.so" > "$out"
      '';
    };
  };
}
