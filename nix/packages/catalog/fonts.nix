# Package identities and provider declarations for fonts.
{ pkgs, ... }:
{
  udev-gothic-nf = {
    pkg = pkgs.udev-gothic-nf;
    winget = null;
    category = "fonts";
  };
}
