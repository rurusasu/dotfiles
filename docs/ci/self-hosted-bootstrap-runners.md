# Self-hosted bootstrap E2E runners

The Windows and macOS bootstrap jobs are intentionally destructive. Register only disposable machines dedicated to this repository; never attach a workstation used for normal development.

## Repository and Environment protection

1. Register each runner at repository scope, not organization scope.
2. Add the custom `dotfiles-e2e` label while retaining the platform labels:
   - Windows: `self-hosted`, `Windows`, `X64`, `dotfiles-e2e`
   - macOS: `self-hosted`, `macOS`, `ARM64`, `dotfiles-e2e`
3. Create the GitHub Environment `destructive-e2e`, add required reviewers, and restrict deployment branches to protected branches.
4. Verify the workflow gate still requires a same-repository pull request before approving a deployment. Fork pull requests must never receive a self-hosted runner.

Each runner must use a dedicated account. Do not sign in to 1Password, GitHub, iCloud, a browser profile, or any other personal service, and do not store personal secrets on the machine. Repository checkout credentials are disabled after checkout.

## Required privileges

The Windows runner account must be a local administrator so the non-interactive service can perform elevation-required setup without a UAC desktop prompt. Enable WSL2 virtualization before registering the runner.

The macOS runner account needs passwordless `sudo` only for the commands used by Nix installation and `darwin-rebuild`. Keep the sudoers rule narrow and remove it with the runner.

Install or permit Docker Desktop on both machines and complete the applicable Docker Desktop license acceptance before the first run. The E2E workflow exercises Linux containers and Docker Compose; Apple Container is not a substitute for this compatibility test.

## Clean-bootstrap reset

Snapshot each machine immediately after OS updates, runner registration, virtualization setup, and Docker license acceptance. Before testing a new bootstrap branch, reset to that snapshot and confirm:

- no prior dotfiles checkout or Home Manager generation remains;
- Windows has no test NixOS WSL distribution and macOS has no prior nix-darwin generation;
- Docker has no test containers, volumes, images, or custom contexts;
- the dedicated account contains no credentials or personal data.

The workflow itself runs the installer twice without a reset between runs. The first pass proves convergence from the clean snapshot; the second proves idempotency.

## Registration and removal

Download the current runner package and registration command from **Repository settings → Actions → Runners → New self-hosted runner**. Use an ephemeral registration token, install the runner as a service under the dedicated account, and confirm all four expected labels before approving a job.

After the test campaign, stop and uninstall the service, remove the runner in repository settings, delete the local runner directory, revoke any temporary credentials, and destroy or reset the machine snapshot. Never reuse a destructive E2E machine as a personal workstation.
