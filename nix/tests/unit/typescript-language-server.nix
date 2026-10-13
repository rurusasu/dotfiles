{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "x86_64-linux";
  brokenHash = "sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo=";
  correctedHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
  source = pkgs.writeText "typescript-language-server-test-source" "upstream-source-fixture";
  mkPackage =
    {
      version ? "6.0.2",
      hash ? brokenHash,
      hasPnpmDeps ? true,
    }:
    pkgs.stdenvNoCC.mkDerivation (
      finalAttrs:
      {
        pname = "typescript-language-server";
        inherit version;
        src = source;
        nativeBuildInputs = [ pkgs.nodejs ];
        dontUnpack = true;
        buildCommand = ''mkdir -p "$out"'';
        doInstallCheck = true;
        installCheckPhase = ''test -d "$out"'';
        meta.mainProgram = "typescript-language-server";
        passthru.upstreamMarker = "preserve-upstream-passthru";
      }
      // pkgs.lib.optionalAttrs hasPnpmDeps {
        # Use the real overridable fetcher; these value tests never build it.
        pnpmDeps = pkgs.fetchPnpmDeps {
          inherit (finalAttrs) pname version src;
          inherit hash;
          fetcherVersion = 4;
        };
      }
      // pkgs.lib.optionalAttrs (!hasPnpmDeps) {
        offlineCache = source;
      }
    );
  repair =
    package:
    pkgs.callPackage ../../modules/typescript-language-server/package.nix {
      typescript-language-server = package;
    };
  broken = mkPackage { };
  repaired = repair broken;
  legacy = mkPackage {
    version = "5.3.0";
    hasPnpmDeps = false;
  };
  withoutPnpm = mkPackage { hasPnpmDeps = false; };
  corrected = mkPackage { hash = correctedHash; };
  otherVersion = mkPackage { version = "6.0.3"; };
  otherHash = mkPackage { hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; };
in
{
  testTypescriptLanguageServerRepairsKnownPnpmHash = {
    expr = repaired.pnpmDeps.outputHash;
    expected = correctedHash;
  };

  testTypescriptLanguageServerPreservesLegacyYarnPackage = {
    expr = (repair legacy).drvPath;
    expected = legacy.drvPath;
  };

  testTypescriptLanguageServerPreservesPackageWithoutPnpmDeps = {
    expr = (repair withoutPnpm).drvPath;
    expected = withoutPnpm.drvPath;
  };

  testTypescriptLanguageServerPreservesCorrectedPnpmPackage = {
    expr = (repair corrected).drvPath;
    expected = corrected.drvPath;
  };

  testTypescriptLanguageServerPreservesOtherVersions = {
    expr = (repair otherVersion).drvPath;
    expected = otherVersion.drvPath;
  };

  testTypescriptLanguageServerPreservesOtherPnpmHashes = {
    expr = (repair otherHash).drvPath;
    expected = otherHash.drvPath;
  };

  testTypescriptLanguageServerPreservesUpstreamPackageAttributes = {
    expr = {
      inherit (repaired)
        pname
        version
        buildCommand
        doInstallCheck
        installCheckPhase
        upstreamMarker
        ;
      src = repaired.src.drvPath;
      nativeBuildInputs = map (package: package.drvPath) repaired.nativeBuildInputs;
      mainProgram = repaired.meta.mainProgram;
      dependencySource = repaired.pnpmDeps.src.drvPath;
      fetcherVersion = repaired.pnpmDeps.fetcherVersion;
    };
    expected = {
      pname = "typescript-language-server";
      version = "6.0.2";
      src = source.drvPath;
      buildCommand = ''mkdir -p "$out"'';
      doInstallCheck = true;
      installCheckPhase = ''test -d "$out"'';
      upstreamMarker = "preserve-upstream-passthru";
      nativeBuildInputs = [ pkgs.nodejs.drvPath ];
      mainProgram = "typescript-language-server";
      dependencySource = source.drvPath;
      fetcherVersion = 4;
    };
  };
}
