# Package identities and provider declarations for lsp.
{ pkgs, lib, ... }:
{
  nixd = {
    pkg = pkgs.nixd;
    winget = null;
    category = "lsp";
  };

  ty = {
    pkg = pkgs.ty;
    winget = "astral-sh.ty";
    category = "lsp";
  };

  ruff = {
    pkg = pkgs.ruff;
    winget = "astral-sh.ruff";
    category = "lsp";
  };

  yaml-language-server = {
    pkg = pkgs.yaml-language-server;
    winget = null;
    category = "lsp";
    support.windows = {
      provider = "pnpm";
      source = "npm";
      identity = "yaml-language-server";
    };
  };

  taplo = {
    pkg = pkgs.taplo;
    winget = "tamasfe.taplo";
    category = "lsp";
  };

  bash-language-server = {
    pkg = pkgs.bash-language-server;
    winget = null;
    category = "lsp";
    support.windows = {
      provider = "pnpm";
      source = "npm";
      identity = "bash-language-server";
    };
  };

  lua-language-server = {
    pkg = pkgs.lua-language-server;
    winget = "LuaLS.lua-language-server";
    category = "lsp";
  };

  stylua = {
    pkg = pkgs.stylua;
    winget = "JohnnyMorganz.StyLua";
    category = "lsp";
  };

  marksman = {
    pkg = pkgs.marksman;
    winget = "Artempyanykh.Marksman";
    category = "lsp";
  };

  gopls = {
    pkg = pkgs.gopls;
    winget = null;
    category = "lsp";
  };

  rust-analyzer = {
    pkg = lib.hiPrio pkgs.rust-analyzer;
    winget = "Rustlang.rust-analyzer";
    category = "lsp";
  };

  rustfmt = {
    pkg = lib.hiPrio pkgs.rustfmt;
    winget = null;
    category = "lsp";
  };

  astro-language-server = {
    pkg = pkgs.astro-language-server;
    winget = null;
    category = "lsp";
  };

  oxlint = {
    pkg = pkgs.oxlint;
    winget = "oxc-project.oxlint";
    category = "lsp";
  };

  typescript-language-server = {
    pkg = pkgs.typescript-language-server;
    winget = null;
    category = "lsp";
    support.windows = {
      provider = "pnpm";
      source = "npm";
      identity = "typescript-language-server";
    };
  };
}
