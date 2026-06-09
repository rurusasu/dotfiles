{
  pkgs,
  src ? null,
  ...
}:
let
  upstreamSrc = pkgs.fetchFromGitHub {
    owner = "d-kuro";
    repo = "gwq";
    rev = "v0.1.1";
    sha256 = "044cjn57373zsz0v283012masgiibjwv1fhzqz7pfnl3ncariw1i";
  };
in
pkgs.buildGoModule {
  pname = "gwq";
  version = if src == null then "0.1.1" else "unstable";

  src = if src == null then upstreamSrc else src;

  vendorHash = "sha256-4K01Xf1EXl/NVX1loQ76l1bW8QglBAQdvlZSo7J4NPI=";

  doCheck = false;

  meta = {
    description = "Manage git worktrees like ghq manages repositories";
    homepage = "https://github.com/d-kuro/gwq";
    license = pkgs.lib.licenses.mit;
    mainProgram = "gwq";
  };
}
