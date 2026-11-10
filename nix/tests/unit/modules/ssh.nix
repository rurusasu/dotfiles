{ fixtures }:
{
  testDisabledSshLeavesUserConfigurationUnmanaged = {
    expr =
      (fixtures.mkHome "x86_64-linux" [
        ({ lib, ... }: {
          programs.ssh.enable = lib.mkForce false;
          dotfiles.onePassword.enable = lib.mkForce false;
        })
      ]).config.home.file
        ? ".ssh/config";
    expected = false;
  };
}
