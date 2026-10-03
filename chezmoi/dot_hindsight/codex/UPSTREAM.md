# Hindsight Codex integration provenance

- Repository: https://github.com/vectorize-io/hindsight
- Revision: 3a399343b377b13324e880261ee9ac5ae96dddcd
- Source: hindsight-integrations/codex/scripts
- Vendored: 2026-08-27

The hook configuration is merged into the existing dotfiles-managed Codex
hooks file. Local connection and bank overrides live in ../codex.json.
The vendored connection layer has a local `autoStartDaemon` switch so the
dotfiles-managed shared Docker endpoint degrades without launching an embedded
fallback service.

The local retention contract keeps both `chunked` and `full-session` supported.
The upstream-derived install settings retain their `full-session` default;
dotfiles' `../codex.json` selects `chunked` with a one-hook cadence and one
overlap turn. Local comments describe this active mode without the former
`legacy` label. This is a documentation and contract-test clarification, not
a retention migration: config precedence, payload selection and document ID
generation are unchanged.

See [Codex retention operation](../../../docs/hermes-agent/hindsight-memory.md#codex-retention)
and `tests/python/test_hindsight_retain.py` in the dotfiles source repository
for the mode/override contract. These source-repository paths are not available
from the deployed `~/.hindsight/codex` directory.
