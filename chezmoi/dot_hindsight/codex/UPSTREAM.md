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
