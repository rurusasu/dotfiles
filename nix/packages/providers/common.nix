{ pkgs, lib }:
let
  supports =
    package: system:
    package != null && builtins.elem system (package.meta.platforms or lib.platforms.all);

  providerSource =
    provider:
    {
      nix = "nixpkgs";
      "homebrew-cask" = "homebrew";
      "homebrew-formula" = "homebrew";
      winget = "winget";
      msstore = "msstore";
      npm = "npm";
      pnpm = "npm";
    }
    .${provider} or null;

  platformKey =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "darwin"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "linux"
    else
      "windows";

in
{
  inherit supports providerSource platformKey;
}
