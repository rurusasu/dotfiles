# Validate the normalized report against provider and host-platform contracts.
{
  pkgs,
  lib,
  catalog,
  supportReport,
  supports,
  platformKey,
}:
let
  hasValue = value: value != null && value != "";
  providerAllowedFields =
    provider:
    if provider == null then
      [ "unsupported" ]
    else if provider == "nix" then
      [
        "provider"
        "source"
        "identity"
        "nixAttr"
        "appName"
        "bundleId"
        "executable"
        "command"
        "versionArgs"
      ]
    else if provider == "homebrew-cask" then
      [
        "provider"
        "source"
        "identity"
        "cask"
      ]
    else if provider == "homebrew-formula" then
      [
        "provider"
        "source"
        "identity"
        "formula"
      ]
    else if
      builtins.elem provider [
        "winget"
        "msstore"
        "npm"
        "pnpm"
      ]
    then
      [
        "provider"
        "source"
        "identity"
      ]
    else if provider == "system-manager" then
      [
        "provider"
        "source"
        "identity"
        "nixAttr"
        "systemModule"
      ]
    else
      [
        "provider"
        "source"
        "identity"
      ];

  providerErrorsFor =
    name: support:
    lib.concatMap
      (
        platform:
        let
          platformData = support.${platform} or { };
          provider = platformData.provider or null;
          unsupported = platformData.unsupported or null;
          entry = catalog.${name} or { };
          package = entry.pkg or null;
          prefix = "${name}: ${platform}: ";
          activePlatform = platform == platformKey;
          extraFields = builtins.filter (field: !(builtins.elem field (providerAllowedFields provider))) (
            builtins.attrNames platformData
          );
          providerSpecificErrors =
            lib.optional (
              provider == "homebrew-cask" && !hasValue (platformData.cask or null)
            ) "${prefix}homebrew-cask provider requires cask"
            ++ lib.optional (
              provider == "homebrew-formula" && !hasValue (platformData.formula or null)
            ) "${prefix}homebrew-formula provider requires formula"
            ++ lib.optional (
              provider == "system-manager" && !hasValue (platformData.systemModule or null)
            ) "${prefix}system-manager provider requires systemModule";
        in
        lib.optional (
          provider == null && (unsupported == null || unsupported == "")
        ) "${prefix}missing provider or reviewed unsupported reason"
        ++ lib.optional (
          provider != null && unsupported != null
        ) "${prefix}provider and unsupported cannot coexist"
        ++ lib.optional (
          provider != null && !hasValue (platformData.source or null)
        ) "${prefix}provider requires source"
        ++ lib.optional (
          provider != null && !hasValue (platformData.identity or null)
        ) "${prefix}provider requires identity"
        ++ lib.optional (
          (platformData.source or null) == "nixpkgs" && !hasValue (platformData.nixAttr or null)
        ) "${prefix}source = nixpkgs requires nixAttr"
        ++ lib.optional (
          provider == "nix" && activePlatform && (package == null || !lib.isDerivation package)
        ) "${prefix}nix provider requires a derivation"
        ++ lib.optional (
          provider == "nix"
          && activePlatform
          && package != null
          && lib.isDerivation package
          && !supports package pkgs.stdenv.hostPlatform.system
        ) "${prefix}nix provider derivation does not support ${platform}"
        ++ map (
          field:
          if provider == null then
            "${prefix}providerless metadata cannot include ${field}"
          else
            "${prefix}${provider} provider cannot include ${field}"
        ) extraFields
        ++ lib.optional (
          provider == "nix" && ((platformData.cask or null) != null || (platformData.formula or null) != null)
        ) "${prefix}catalog ID appears in both Nix and Homebrew resolution"
        ++ providerSpecificErrors
      )
      [
        "windows"
        "darwin"
        "linux"
      ];

  providerErrors = lib.concatMap (name: providerErrorsFor name supportReport.${name}) (
    lib.attrNames supportReport
  );
in
providerErrors
