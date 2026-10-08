# Package identities and provider declarations for dev.
{ pkgs, ... }:
{
  nodejs = {
    pkg = pkgs.nodejs;
    winget = "OpenJS.NodeJS.LTS";
    category = "dev";
  };

  python3 = {
    pkg = pkgs.python3;
    winget = null;
    category = "dev";
  };

  go = {
    pkg = pkgs.go;
    winget = "GoLang.Go";
    category = "dev";
  };

  rustup = {
    pkg = pkgs.rustup;
    winget = "Rustlang.Rustup";
    category = "dev";
  };

  gnumake = {
    pkg = pkgs.gnumake;
    winget = null;
    category = "dev";
  };

  cmake = {
    pkg = pkgs.cmake;
    winget = null;
    category = "dev";
  };

  gwq = {
    pkg = pkgs.gwq;
    winget = null;
    category = "dev";
  };

  uv = {
    pkg = pkgs.uv;
    winget = "astral-sh.uv";
    category = "dev";
  };

  devcontainer = {
    pkg = pkgs.devcontainer;
    winget = null;
    npm = "@devcontainers/cli";
    category = "dev";
  };

  bats = {
    pkg = pkgs.bats;
    winget = null; # Windows 対応せず (NixOS/WSL のみ)
    category = "dev";
  };

  imagemagick = {
    pkg = pkgs.imagemagick;
    winget = "ImageMagick.ImageMagick";
    category = "dev";
  };

  ghostscript = {
    pkg = pkgs.ghostscript;
    winget = null; # winget カタログ未収録 — Windows は https://ghostscript.com から手動インストール
    category = "dev";
  };

  poppler-utils = {
    pkg = pkgs.poppler-utils;
    winget = "oschwartz10612.Poppler";
    category = "dev";
  };

  dprint = {
    pkg = pkgs.dprint;
    winget = "dprint.dprint";
    category = "dev";
  };

  hadolint = {
    pkg = pkgs.hadolint;
    winget = "hadolint.hadolint";
    category = "dev";
  };

  bun = {
    pkg = pkgs.bun;
    winget = "Oven-sh.Bun";
    category = "dev";
  };

  zig = {
    pkg = pkgs.zig;
    winget = "zig.zig";
    category = "dev";
  };

  tree-sitter = {
    pkg = pkgs.tree-sitter;
    winget = "tree-sitter.tree-sitter-cli";
    category = "dev";
  };
}
