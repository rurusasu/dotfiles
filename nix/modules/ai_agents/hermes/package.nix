{
  package,
  source,
  pkgs,
}:
let
  inherit (pkgs) lib;
  versionLine = lib.findFirst (lib.hasPrefix "__version__ = ") "" (
    lib.splitString "\n" (builtins.readFile "${source}/hermes_cli/__init__.py")
  );
  declared = builtins.match ''__version__ = "([^"]+)"'' versionLine;
  parsedVersion = if declared == null then null else builtins.head declared;
  knownVersion = if parsedVersion == "0.0.0" then null else parsedVersion;
  sourceDate = source.lastModifiedDate or "";
  date = "${builtins.substring 0 4 sourceDate}-${builtins.substring 4 2 sourceDate}-${
    builtins.substring 6 2 sourceDate
  }";
  revision = source.rev or (throw "Hermes version metadata requires an immutable source revision");
  developmentVersion =
    assert builtins.stringLength sourceDate >= 8;
    "unstable-${date}-${builtins.substring 0 8 revision}";
in
if package.version != "0.0.0" then
  package
else
  package.overrideAttrs (
    final: previous:
    let
      # Home Manager may override dependency groups after selecting the package.
      # Always use that resulting runtime and stamp, not the initial package.
      runtime = previous.passthru.hermesVenv;
      originalStamp = previous.passthru.installStampFile or null;
      needsIdentity = knownVersion == null && previous.version == "0.0.0";
      version =
        if previous.version != "0.0.0" then
          previous.version
        else if knownVersion != null then
          knownVersion
        else
          developmentVersion;
      stamp =
        if originalStamp != null && version != previous.version then
          pkgs.runCommand "hermes-version-stamp.json" { } ''
            ${pkgs.jq}/bin/jq --arg version ${lib.escapeShellArg version} \
              '.baseVersion = $version | .displayVersion = $version' \
              ${originalStamp} > "$out"
          ''
        else
          originalStamp;
    in
    {
      inherit version;
      postInstall =
        (previous.postInstall or "")
        + lib.optionalString (stamp != null && stamp != originalStamp) ''
          cp ${stamp} "$out/share/hermes-agent/install-stamp.fixed.json"
          mv "$out/share/hermes-agent/install-stamp.fixed.json" "$out/share/hermes-agent/install-stamp.json"
        ''
        + lib.optionalString needsIdentity ''
          # Keep the official runtime and dependencies; only correct its build identity.
          substituteInPlace "$out/bin/hermes" \
            --replace-fail 'exec "${runtime}/bin/hermes"' \
            'exec "${runtime}/bin/python3" "${./versioned-entrypoint.py}" "${
              lib.replaceStrings [ "-" ] [ "." ] date
            }" "${runtime}/bin/hermes"'
        '';
      passthru =
        previous.passthru
        // {
          hermesDesktop =
            let
              desktop = previous.passthru.hermesDesktop.override (
                {
                  hermesAgent = final.finalPackage;
                }
                // lib.optionalAttrs (stamp != null) { installStampFile = stamp; }
              );
            in
            if desktop.version != "0.0.0" then
              desktop
            else
              desktop.overrideAttrs (previousDesktop: {
                inherit version;
                postInstall = (previousDesktop.postInstall or "") + ''
                  # Electron's About/version API reads the installed package.json.
                  ${pkgs.jq}/bin/jq --arg version ${lib.escapeShellArg version} \
                    '.version = $version' "$out/share/hermes-desktop/package.json" \
                    > "$out/share/hermes-desktop/package.fixed.json"
                  mv "$out/share/hermes-desktop/package.fixed.json" "$out/share/hermes-desktop/package.json"
                '';
              });
        }
        // lib.optionalAttrs (stamp != null) { installStampFile = stamp; };
    }
  )
