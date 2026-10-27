{
  programs.pi-coding-agent = {
    enable = true;
    mutableSettings = true;
    settings = {
      defaultProvider = "openai-codex";
      # Pi only uses the saved default when both provider and model are set.
      defaultModel = "gpt-6.1-terra";
      defaultThinkingLevel = "max";
    };
    # Terra is not yet included in Pi's bundled Codex model catalog.
    models.providers.openai-codex.models = [
      {
        id = "gpt-6.1-terra";
        name = "GPT-6.1 Terra";
        reasoning = true;
        input = [
          "text"
          "image"
        ];
        contextWindow = 500000;
        maxTokens = 128000;
        thinkingLevelMap = {
          minimal = "low";
          xhigh = "xhigh";
          max = "max";
        };
      }
    ];
  };
}
