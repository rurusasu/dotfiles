// mempalace-observe.js — PostToolUse hook for MemPalace
// TODO: Integrate with mempalace CLI (mempalace mine / mempalace diary)
// MemPalace uses stdio MCP, so HTTP-based hooks won't work directly.
// Options:
//   1. Shell out to `mempalace mine` CLI
//   2. Use mempalace_diary_write via MCP client
//   3. Wait for MemPalace HTTP endpoint support

export default function () {
  // Hook disabled pending mempalace integration
  return;
}
