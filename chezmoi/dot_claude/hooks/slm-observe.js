#!/usr/bin/env node
/**
 * PostToolUse hook: observe conversation turns in SuperLocalMemory.
 *
 * Reads tool interaction from CLAUDE_TOOL_* env vars and sends to SLM's
 * observe_conversation MCP tool. If the user message contains explicit
 * memory keywords ("覚えて", "remember this", etc.), also calls remember.
 *
 * SLM_MCP_URL env var controls the endpoint:
 *   - Local tools: http://localhost:3000/mcp (default, Kind NodePort 30300 → host 3000)
 *   - OpenClaw Gateway: http://superlocalmemory:3000/mcp
 */

const SLM_MCP_URL = process.env.SLM_MCP_URL || "http://localhost:3000/mcp";
const TIMEOUT_MS = 5000;

const REMEMBER_PATTERNS = [
  /覚えて/,
  /記憶して/,
  /保存して/,
  /メモして/,
  /remember this/i,
  /save this/i,
  /note this/i,
  /keep this in mind/i,
];

async function callMcp(method, args) {
  const payload = {
    jsonrpc: "2.0",
    id: Date.now(),
    method: "tools/call",
    params: { name: method, arguments: args },
  };
  const resp = await fetch(SLM_MCP_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!resp.ok) {
    console.error(`[slm-observe] HTTP ${resp.status}: ${await resp.text()}`);
  }
}

async function main() {
  const toolName = process.env.CLAUDE_TOOL_NAME || "";
  const toolInput = process.env.CLAUDE_TOOL_INPUT || "";
  const toolResult = process.env.CLAUDE_TOOL_RESULT || "";

  // Skip if no meaningful content
  if (!toolName && !toolInput && !toolResult) return;

  // Build conversation text from available context
  const parts = [];
  if (toolName) parts.push(`[Tool: ${toolName}]`);
  if (toolInput) parts.push(`Input: ${toolInput}`);
  if (toolResult) parts.push(`Result: ${toolResult.slice(0, 2000)}`);
  const conversation = parts.join("\n");

  // Determine source
  const source = process.env.SLM_SOURCE || "claude-code";

  // Send to observe_conversation
  await callMcp("observe_conversation", { conversation, source });

  // Check for explicit remember keywords in input
  if (toolInput && REMEMBER_PATTERNS.some((p) => p.test(toolInput))) {
    await callMcp("remember", { content: toolInput });
  }
}

main().catch((err) => console.error(`[slm-observe] ${err.message}`));
