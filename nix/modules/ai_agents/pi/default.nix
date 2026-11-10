{ config, lib, ... }:
{
  config = lib.mkMerge [
    { programs.pi-coding-agent.enable = true; }
    (lib.mkIf config.programs.pi-coding-agent.enable {
      programs.pi-coding-agent = {
        mutableSettings = true;
        settings = {
          defaultProvider = "strata";
          # Pi only uses the saved default when both provider and model are set.
          defaultModel = "qwen3.8-flash-next-q2_0";
          defaultThinkingLevel = "off";
          compaction = {
            enabled = true;
            reserveTokens = 4096;
            keepRecentTokens = 8192;
          };
        };
        models.providers.strata = {
          baseUrl = "http://127.0.0.1:8080/v1";
          api = "openai-completions";
          # A public placeholder for Pi's provider availability check; localhost
          # Strata does not require authentication.
          apiKey = "strata-local";
          # This local endpoint uses system messages and chat-template thinking
          # controls rather than OpenAI's developer role and reasoning_effort.
          compat = {
            supportsDeveloperRole = false;
            supportsReasoningEffort = false;
          };
          models = [
            {
              id = "qwen3.8-flash-next-q2_0";
              name = "Qwen3.8-Flash-Next (Strata local)";
              reasoning = true;
              input = [ "text" ];
              contextWindow = 32768;
              maxTokens = 4096;
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              samplingParamsByThinkingLevel.off.chat_template_kwargs.enable_thinking = false;
            }
          ];
        };
      };
    })
  ];
}
