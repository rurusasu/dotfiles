{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      missing-source = {
        pkg = pkgs.hello;
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "";
            identity = "missing-source";
            nixAttr = "hello";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      missing = {
        pkg = pkgs.hello;
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            identity = "";
            nixAttr = "";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      missing-cask = {
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "homebrew-cask";
            source = "homebrew";
            identity = "";
            cask = "";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      extra = {
        pkg = pkgs.hello;
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            identity = "extra";
            nixAttr = "hello";
            cask = "wrong";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      orphan = {
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            unsupported = "fixture";
            cask = "stale";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      active-invalid = {
        pkg = "not-a-derivation";
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            identity = "active-invalid";
            nixAttr = "hello";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      active-unsupported = {
        pkg = pkgs.hello.overrideAttrs (_: {
          meta.platforms = [ "x86_64-linux" ];
        });
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            identity = "active-unsupported";
            nixAttr = "hello";
          };
          linux = {
            unsupported = "fixture";
          };
        };
      };
      host-conditional = {
        pkg =
          if pkgs.stdenv.hostPlatform.isDarwin then
            pkgs.hello.overrideAttrs (_: {
              meta.platforms = [ "aarch64-darwin" ];
            })
          else
            pkgs.hello;
        category = "test";
        support = {
          windows = {
            unsupported = "fixture";
          };
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            identity = "host-conditional";
            nixAttr = "hello";
          };
          linux = {
            provider = "nix";
            source = "nixpkgs";
            identity = "host-conditional";
            nixAttr = "hello";
          };
        };
      };
    };
  };
  errors = sets.providerErrors;
in
{
  testPackageCatalogValidationFixtures = {
    expr = {
      missingSource = builtins.elem "missing-source: darwin: provider requires source" errors;
      missingIdentity = builtins.elem "missing: darwin: provider requires identity" errors;
      missingNixAttr = builtins.elem "missing: darwin: source = nixpkgs requires nixAttr" errors;
      missingCask = builtins.elem "missing-cask: darwin: homebrew-cask provider requires cask" errors;
      nixProviderCannotIncludeCask = builtins.elem "extra: darwin: nix provider cannot include cask" errors;
      duplicateNixAndHomebrewResolution = builtins.elem "extra: darwin: catalog ID appears in both Nix and Homebrew resolution" errors;
      providerlessMetadataCannotIncludeCask = builtins.elem "orphan: darwin: providerless metadata cannot include cask" errors;
      activePackageMustBeDerivation = builtins.elem "active-invalid: darwin: nix provider requires a derivation" errors;
      activeDerivationMustSupportHost = builtins.elem "active-unsupported: darwin: nix provider derivation does not support darwin" errors;
      inactiveHostDoesNotValidateDerivation = builtins.filter (
        error: builtins.match ".*host-conditional.*" error != null
      ) errors;
    };
    expected = {
      missingSource = true;
      missingIdentity = true;
      missingNixAttr = true;
      missingCask = true;
      nixProviderCannotIncludeCask = true;
      duplicateNixAndHomebrewResolution = true;
      providerlessMetadataCannotIncludeCask = true;
      activePackageMustBeDerivation = true;
      activeDerivationMustSupportHost = true;
      inactiveHostDoesNotValidateDerivation = [ ];
    };
  };
}
