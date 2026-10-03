# syntax=docker/dockerfile:1
FROM ghcr.io/nixos/nix:2.34.8@sha256:1a711b619c8a713eff32c3f8d8781b3b4d0130cb91c0a57f67e87abfeeb90b01 AS nix

# The distribution libraries also support GitHub Actions' injected Node.js binary.
FROM node:24-bookworm-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6

COPY --from=nix /nix /nix
COPY nix.conf /etc/nix/nix.conf
COPY profile.sh /etc/profile.d/bootstrap-ci-tools.sh

ENV PATH="/opt/ci-tools/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="/root" \
    LANG="C.UTF-8" \
    NIX_SSL_CERT_FILE="/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" \
    SSL_CERT_FILE="/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" \
    PSModulePath="/opt/powershell/Modules" \
    POWERSHELL_TELEMETRY_OPTOUT="1"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool versions are independent of the dotfiles outputs under test.
ARG NIXPKGS_REV=79b35bf0bda5cd110f856aa5b5b2c5ba4460dbf5
RUN nix profile install --profile /opt/ci-tools --option sandbox false \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#bash" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#bats" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#cacert" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#chezmoi" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#coreutils" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#git" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#git-lfs" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#gnugrep" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#gnutar" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#go-task" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#jq" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#powershell" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#procps" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#python314" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#ruby" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#statix" \
      "github:NixOS/nixpkgs/${NIXPKGS_REV}#xz"

# PowerShell expands these variables, not the Docker build shell.
# hadolint ignore=SC2016
RUN mkdir -p /opt/powershell/Modules \
    && pwsh -NoLogo -NoProfile -Command \
      '$ErrorActionPreference = "Stop"; Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.22.0 -Repository PSGallery -Path /opt/powershell/Modules'

COPY check.sh /usr/local/libexec/check-bootstrap-ci-tools.sh
RUN bash /usr/local/libexec/check-bootstrap-ci-tools.sh

# CI builds need a writable local Nix store. No user configuration is applied here.
ENTRYPOINT []
CMD ["bash"]
