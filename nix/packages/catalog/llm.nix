# Unix DSH is supplied by nix/modules/dsh.nix; Windows uses npm.
_: {
  dsh = {
    pkg = null;
    npm = "@deepseek-ai/dsh";
    category = "llm";
    support = {
      windows = {
        provider = "npm";
        source = "npm";
        identity = "@deepseek-ai/dsh";
      };
      darwin.unsupported = "Unix installation is owned by the dsh Home Manager module";
      linux.unsupported = "Unix installation is owned by the dsh Home Manager module";
    };
  };
}
