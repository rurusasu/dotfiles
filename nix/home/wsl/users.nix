# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { ... }:
    {
      imports = [ ../common.nix ];

      # WSL: GitHub への HTTPS push は Windows 側の Git Credential Manager に委譲する。
      # WSL 内で credential.helper を未設定にすると `git push` が TTY 入力待ちでハング
      # する（chezmoi が WSL 内まで適用されないためここで宣言的に補う）。
      # GCM 本体のパスは WSL 限定なので home-manager の WSL プロファイルに置く。
      programs.git = {
        enable = true;
        extraConfig = {
          credential."https://github.com".helper =
            "/mnt/c/Program\\ Files/Git/mingw64/bin/git-credential-manager.exe";
          credential."https://gist.github.com".helper =
            "/mnt/c/Program\\ Files/Git/mingw64/bin/git-credential-manager.exe";
        };
      };
    };
}
