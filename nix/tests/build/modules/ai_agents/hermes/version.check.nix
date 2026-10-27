{
  inputs,
  pkgs,
  files,
}:
{
  hermes-version = (
    let
      # Build-only probe against upstream's CLI initializer. The application keeps
      # its bundled interpreter; this avoids building its entire optional venv here.
      python = "${pkgs.python3}/bin/python3";
      probe = pkgs.writeText "hermes-version-probe.py" ''
        import json
        import sys
        from hermes_cli import __release_date__
        print(json.dumps({"date": __release_date__, "args": sys.argv[1:]}))
        raise SystemExit(17)
      '';
    in
    pkgs.runCommand "hermes-version-entrypoint-check" { } ''
      set +e
      PYTHONPATH=${inputs.hermes-agent} ${python} ${
        files.nix.modules.ai_agents.hermes."versioned-entrypoint.py"
      } \
        2026.10.26 ${probe} "argument with spaces" --version > result.json
      status=$?
      set -e
      test "$status" -eq 17
      ${pkgs.jq}/bin/jq -e \
        '.date == "2026.10.26" and .args == ["argument with spaces", "--version"]' result.json
      touch "$out"
    ''
  );
}
