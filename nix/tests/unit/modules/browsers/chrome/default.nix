{ homeConfigurations }:
{
  testWslChromeUsesJapaneseLanguage = {
    expr = homeConfigurations.wsl.config.programs.chromium.commandLineArgs;
    expected = [ "--lang=ja" ];
  };
}
