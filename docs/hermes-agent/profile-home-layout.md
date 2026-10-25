# Hermes Profile Ownership

The official Home Manager module manages the root home at
`${HERMES_HOME}`, normally `~/.hermes`. Named runtime homes live under
`~/.hermes/profiles/<name>`.

Named configuration belongs in its Git source, including profile-specific
secret references. Install a Git URL or a local profile directory with
`hermes profile install <source>`; update it with
`hermes profile update <name>`. The distribution manifest supplies the name.
Runtime homes contain local auth, sessions and memory; they are separate from
the configuration source.

Use [Hermes Operations](bootstrap.md) for commands.
