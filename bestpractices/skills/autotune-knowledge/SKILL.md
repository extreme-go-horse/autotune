---
name: autotune-knowledge
description: Claude Code setup optimization knowledge. Use when writing or editing CLAUDE.md, settings.json, hooks, permissions, .mcp.json, or any configuration file. Also use when user asks about Claude Code best practices, performance, token economy, or cost optimization.
allowed-tools: Read, Grep, Glob
---

# Autotune Knowledge

Setup optimization knowledge base derived from Claude Code source code. Provides heuristics for writing better configuration and avoiding common pitfalls.

## When This Activates

- Writing or editing CLAUDE.md (any level)
- Modifying settings.json (permissions, env vars, modes)
- Configuring hooks or hook scripts
- Setting up MCP servers or modifying .mcp.json
- User asks about best practices, token costs, or setup optimization

## What To Do

1. Read the relevant heuristic file(s) from `heuristics/` based on the area being modified
2. Check the proposed change against the detection rules
3. If a rule matches, warn the user with the finding ID and explanation
4. Reference `references/BEST_PRACTICES.md` for the user-facing guidance

## Heuristic Files

- `heuristics/permissions.md` — permission settings, allow/deny rules, defaultMode
- `heuristics/claudemd.md` — CLAUDE.md token weight, bloat detection, content migration
- `heuristics/model-config.md` — caching, thinking tokens, output limits, subagent models
- `heuristics/plugins.md` — plugin health, ghost plugins, namespace conflicts
- `heuristics/mcp.md` — MCP server health, timeouts, dead server detection

## Key Principles

- Every hot file (CLAUDE.md, settings.json, MEMORY.md, .mcp.json) costs tokens every turn
- Token estimate: `char_count / 3` for markdown content
- Prompt caching saves ~80% — never disable without specific reason
- Permission checks happen at execution time, not startup — allow list is zero overhead
- Hooks are snapshotted at startup — mid-session changes don't apply
- Semantic enforcement is best-effort — critical guardrails must be mechanical (shell scripts)
