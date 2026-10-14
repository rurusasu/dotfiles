# Keep Chrome's Linux UI and GTK dialogs on the same Japanese UTF-8 locale.
# Linux Chrome also reads LANGUAGE; --lang alone does not set every UI locale.
{ pkgs }:
let
  # The WSL host runs its own fcitx5 service without NixOS inputMethod's cache.
  # GTK3 needs this registration file to discover the installed fcitx plugin.
  gtk3ImmodulesCache =
    pkgs.runCommand "chrome-fcitx-gtk3-immodules.cache"
      {
        nativeBuildInputs = [ pkgs.gtk3 ];
        preferLocalBuild = true;
        allowSubstitutes = false;
        disallowedReferences = [ (pkgs.lib.getDev pkgs.gtk3) ];
      }
      ''
        gtk-query-immodules-3.0 "${pkgs.fcitx5-gtk}/lib/gtk-3.0/3.0.0/immodules/im-fcitx5.so" > "$out"
      '';
in
pkgs.google-chrome.overrideAttrs (previous: {
  postFixup = (previous.postFixup or "") + ''
    wrapProgram "$out/bin/google-chrome-stable" \
      --set LANG ja_JP.UTF-8 \
      --set LC_ALL ja_JP.UTF-8 \
      --set LANGUAGE ja \
      --set GTK_IM_MODULE_FILE "${gtk3ImmodulesCache}" \
      --add-flags --lang=ja
  '';
})
