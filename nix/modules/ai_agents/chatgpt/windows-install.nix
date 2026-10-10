{
  msstore = [ "9PLM9XGG6VKS" ];
  windowsOnlySupport."9PLM9XGG6VKS" = {
    windows = {
      provider = "msstore";
      source = "msstore";
      identity = "9PLM9XGG6VKS";
    };
    darwin.unsupported = "Windows Store desktop application";
    linux.unsupported = "Windows Store desktop application";
  };
  # Keep the upstream AppX identity even though the app is managed as ChatGPT.
  msstoreVerifyById."9PLM9XGG6VKS" = {
    type = "appxLaunchTarget";
    command = "OpenAI.Codex";
    args = [ "OpenAI.Codex_2p2nqsd0c76g0!App" ];
  };
  wingetCiSkipInstall."9PLM9XGG6VKS" = true;
}
