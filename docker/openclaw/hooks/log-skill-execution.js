#!/usr/bin/env node
/**
 * PostToolUse hook: log skill tool executions to Cognee MCP.
 *
 * Reads tool name from CLAUDE_TOOL_NAME env var (Claude Code PostToolUse hook spec).
 * If the tool is an OpenClaw MCP skill tool (prefixed with "cognee-skills__"),
 * sends a JSON-RPC call to the Cognee MCP Streamable HTTP endpoint to log the execution.
 *
 * Errors are logged to stderr and never block the agent response.
 */

const COGNEE_MCP_URL = process.env.COGNEE_MCP_URL || "http://cognee-mcp-skills:8000/mcp";
const SKILL_TOOL_PREFIX = "cognee-skills__";

async function main() {
  const toolName = process.env.CLAUDE_TOOL_NAME;
  if (!toolName) return;

  // Only log executions of skill-related tools, not the self-improvement tools themselves
  const skipTools = [
    "log_skill_execution",
    "search_skill_history",
    "get_skill_status",
    "get_skill_improvements",
    "amend_skill",
    "evaluate_amendment",
    "rollback_skill",
    "ingest_transcript",
    "batch_cognify",
    "search_knowledge",
  ];

  // Check if this is a skill tool execution
  let skillName = null;
  if (toolName.startsWith(SKILL_TOOL_PREFIX)) {
    const shortName = toolName.slice(SKILL_TOOL_PREFIX.length);
    if (skipTools.includes(shortName)) return;
    skillName = shortName;
  } else {
    // Not a cognee-skills MCP tool, skip
    return;
  }

  const toolResult = process.env.CLAUDE_TOOL_RESULT || "";
  const success = !toolResult.toLowerCase().includes('"error"');

  const rpcPayload = {
    jsonrpc: "2.0",
    id: Date.now(),
    method: "tools/call",
    params: {
      name: "log_skill_execution",
      arguments: {
        skill_name: skillName,
        agent: "openclaw-hook",
        task_description: `Auto-logged by PostToolUse hook for tool: ${toolName}`,
        success: success,
        error: success ? null : "Tool result contained error indicator",
      },
    },
  };

  try {
    const resp = await fetch(COGNEE_MCP_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(rpcPayload),
      signal: AbortSignal.timeout(5000),
    });
    if (!resp.ok) {
      console.error(`[log-skill-hook] HTTP ${resp.status}: ${await resp.text()}`);
    }
  } catch (err) {
    console.error(`[log-skill-hook] ${err.message}`);
  }
}

main().catch((err) => console.error(`[log-skill-hook] ${err.message}`));
