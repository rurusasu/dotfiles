# Package Test Boundaries Design

## Context

The repository currently mixes package catalog assertions, Nix configuration
evaluation, derivation builds, and runtime contracts. In particular,
`tests/bash/package_catalog.bats` contains 46 cases: most are pure catalog or
Nix assertions, while a smaller set validates generated artifacts or runtime
behavior. The Nix-native suite already exists, but it does not own all pure
package assertions, and custom package derivations are not represented as a
single focused build-check surface.

## Goals

- Make pure package/provider/selection/source-shape assertions authoritative
  `nix-unit` tests.
- Ensure custom package derivations are exercised by real Nix builds, including
  their build and install phases.
- Keep tests that require executable behavior, filesystem state, signatures,
  external tools, or platform services in the appropriate runtime suite.
- Make CI, task commands, ownership checks, and documentation describe the
  same boundaries.

## Non-goals

- Do not replace macOS, Windows, Docker, systemd, or service-runtime tests with
  Nix expression evaluation.
- Do not build every upstream nixpkgs package referenced by the catalog merely
  because it is selected in a package set.
- Do not perform live privileged activation as part of the package build
  checks.

## Proposed test layers

### Nix-unit layer

Move the pure package catalog cases from `tests/bash/package_catalog.bats` into
one or more files under `nix/tests/packages/`, using `{ expr, expected }`
attributes and registering them from `nix/flakes/tests.nix`. This includes
provider metadata, platform selection, package-set membership, catalog
validation, and source-shape assertions that only inspect repository data.

The Bats cases that currently run `nix eval` for these assertions will be
removed. The ownership test will then enforce that no package catalog Bats
case reintroduces this boundary violation.

### Package build layer

Expose focused checks for the repository's custom package derivations through
the flake `checks` output on the systems they support. These checks will point
at the actual derivations (or a small check derivation when artifact
assertions are required), so Nix executes the package build and install
phases. The set will be explicit and limited to custom packages, rather than
forcing all nixpkgs dependencies in the catalog to build on every check.

### Runtime and artifact layer

Retain Bats coverage for behavior that requires shell execution, external
command stubs, filesystem mutation, manifest byte-for-byte comparison, signed
bundle inspection, or host-specific behavior. These cases remain separate
from `nix-unit` because evaluating a Nix expression cannot prove those
runtime properties.

## Migration outline

1. Classify the 46 existing package catalog cases against the three layers.
2. Add the Nix-native package test files and register them in the flake.
3. Port the pure cases and remove their Bats implementations.
4. Add explicit custom-package build checks and focused task/CI invocation.
5. Keep the runtime/artifact Bats cases and adjust their surrounding naming or
   documentation only where needed.
6. Update `nix/tests/ownership.nix`, `nix/tests/home/README.md`, CI routing,
   and task descriptions.
7. Run focused Nix-unit, package-build, and runtime tests, then run the
   relevant full suites where the environment supports them.

## Acceptance criteria

- Pure package assertions no longer execute `nix eval` from Bats.
- The migrated assertions pass in the focused `nix-unit` check.
- Explicit custom package build checks execute successfully on supported
  systems.
- Runtime/artifact Bats coverage remains present and passing.
- Ownership documentation and CI routing match the resulting test layout.
- No unrelated package, installer, or platform behavior changes are included.

## Risks and mitigations

- Building custom packages may require network downloads and platform-specific
  builders. Keep the package list explicit, preserve existing caches, and
  route checks only to supported systems.
- Porting source-shape assertions can accidentally test implementation text
  rather than behavior. Prefer evaluating the same public package-set outputs;
  retain source-shape checks only where no stable semantic boundary exists.
- Removing Bats cases can reduce runtime coverage if classification is wrong.
  Preserve the five existing runtime/artifact contracts and verify the final
  Bats count and ownership checks in CI.
