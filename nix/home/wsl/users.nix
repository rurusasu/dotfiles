# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { ... }:
    let
      # GCM のパスには空白 (`Program Files`) が含まれるため、git が helper 値を
      # `sh -c` に渡す前にトークン分割しないようリテラルなダブルクォートで包む。
      # home-manager の INI 出力は埋め込み `"` を `\"` にエスケープし、git は
      # 読み出し時に外側のクォートを除去するので、最終的に shell に届くのは
      # 1 トークンのクォート付きパスになる。
      gcmHelper = ''"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"'';
    in
    {
      imports = [ ../common.nix ];

      # WSL: GitHub への HTTPS push は Windows 側の Git Credential Manager に委譲する。
      # WSL 内で credential.helper が未設定だと、git の認証フェーズで stdin 入力待ちと
      # なり非対話シェル経由 (`task push` 等) では無進捗でブロックする
      # （chezmoi が WSL 内まで適用されないためここで宣言的に補う）。
      # GCM 本体のパスは WSL 限定なので home-manager の WSL プロファイルに置く。
      programs.git = {
        enable = true;
        settings = {
          credential."https://github.com".helper = gcmHelper;
          credential."https://gist.github.com".helper = gcmHelper;
        };
      };
    };
}
