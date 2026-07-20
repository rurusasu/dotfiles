{ inputs }:
let
  lib = inputs.nixpkgs.lib;

  withoutAuditableCargo =
    nativeBuildInputs:
    lib.filter (input: !(lib.hasPrefix "auditable-cargo" (input.name or ""))) nativeBuildInputs;

  overrideWorkmux =
    pkgs: package:
    package.overrideAttrs (
      old:
      {
        doCheck = false;
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) {
        nativeBuildInputs = withoutAuditableCargo (old.nativeBuildInputs or [ ]) ++ [
          pkgs.llvmPackages_21.lld
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libiconv ];
        RUSTFLAGS = lib.concatStringsSep " " (
          lib.filter (flag: flag != "") [
            (old.RUSTFLAGS or "")
            "-C linker=${pkgs.llvmPackages_21.lld}/bin/ld64.lld"
            "-C linker-flavor=ld64.lld"
            "-C link-arg=-L${pkgs.libiconv}/lib"
          ]
        );
      }
    );
in
{
  mkOverlay = workmuxPackageFor: final: prev: {
    workmux = overrideWorkmux final (workmuxPackageFor prev.stdenv.hostPlatform.system);
  };
}
