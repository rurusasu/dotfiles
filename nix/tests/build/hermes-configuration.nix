{ pkgs }:
let
  python = pkgs.python3.withPackages (packages: [ packages.pyyaml ]);
  manifests =
    map
      (hermesHome: {
        home = hermesHome;
        path = pkgs.writeText "hermes-bootstrap-manifest.yaml" (
          import ../../modules/ai_agents/hermes/manifest.nix { inherit hermesHome; }
        );
      })
      [
        "/home/test-user/.hermes"
        "/Users/test-user/.hermes"
      ];
  manifestCases = pkgs.writeText "hermes-manifest-cases.json" (builtins.toJSON manifests);
in
pkgs.runCommand "hermes-configuration-check"
  {
    nativeBuildInputs = [
      python
      pkgs.jq
      pkgs.yq-go
    ];
  }
  ''
    # Validate the generated configuration with the parser used by bootstrap.
    export PYTHONPATH=${../../../scripts/python}
    python - ${manifestCases} <<'PY'
    import json
    import os
    import sys
    from pathlib import Path

    from hermes_bootstrap.manifest import load_manifest

    for case in json.loads(Path(sys.argv[1]).read_text()):
        os.environ["HERMES_HOME"] = case["home"]
        manifest = load_manifest(Path(case["path"]))
        assert all(source.source_commit for source in (manifest.root_distribution, *manifest.profiles))
    PY

    yq -o=json '.' ${../../../docker/hermes-service/compose.yml} > compose.json
    jq -e '
      .services as $services
      | $services.chromium as $chromium
      | $services["browser-mcp"] as $browser
      | $services["xapi-mcp"] as $xapi
      | all($services[]; all(.ports[]; startswith("127.0.0.1:")))
        and ($chromium | has("platform") | not)
        and ($chromium.ports == ["127.0.0.1:''${HERMES_BROWSER_VIEW_PORT:-6080}:6080"])
        and ($browser.ports == ["127.0.0.1:8765:8080"])
        and ($xapi.ports == ["127.0.0.1:8766:8080"])
        and ($chromium.networks == $browser.networks and $browser.networks == $xapi.networks)
        and ($browser.depends_on.chromium.condition == "service_healthy")
        and ($browser.command | index("--browser-url=http://chromium:9222") != null)
        and ($browser.command | index("--experimentalPageIdRouting") != null)
        and ($browser.command as $command
          | ($command | index("--requestTimeout")) as $index
          | $index != null and $command[$index + 1] == "120000")
        and ($xapi.volumes == [{
          type: "bind",
          source: "''${HERMES_DATA_DIR:-''${USERPROFILE:-''${HOME}}/.hermes}/.xurl",
          target: "/root/.xurl"
        }])
    ' compose.json
    touch "$out"
  ''
