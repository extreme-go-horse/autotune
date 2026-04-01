# MCP Server Heuristics

Source: `tools/mcp`, `server/`

## Detection Rules

### Critical
- **Dead server**: MCP server fails to respond to ping within `thresholds.mcp_timeout_ms` → `mcp-dead-001`. Dead servers slow every session start.

### Warning
- **Slow server**: Server responds but > 2000ms → `mcp-slow-001`. Consider raising MCP_TIMEOUT.
- **No timeout configured**: `MCP_TIMEOUT` not in env and server takes > 1000ms → `mcp-timeout-001`.
- **Output tokens default**: Heavy server (known data-intensive) using default `MAX_MCP_OUTPUT_TOKENS` (25000) → `mcp-output-001`.
- **Duplicate server**: Two server configs pointing to same command+args → `mcp-dup-001`.

### Info
- **Server count**: More than 5 MCP servers → `mcp-count-001`. Each adds discovery overhead.
- **Unused tools**: Server provides tools never used in recent sessions → `mcp-unused-001` (requires transcript access).

## Health Check Method

1. Read `.mcp.json` (global and project-level)
2. For each server:
   - Attempt connection (timeout: per-server cap from config, total cap 5s for all)
   - Measure response time
   - List available tools
3. Parallel ping — fire all health checks simultaneously, collect results

## Fix Descriptors

| Finding | Fix type | Target | Patch |
|---------|----------|--------|-------|
| mcp-dead-001 | mcp-disable | .mcp.json | Remove or comment out dead server |
| mcp-slow-001 | env-set | settings.json env | Set MCP_TIMEOUT for slow server |
| mcp-timeout-001 | env-set | settings.json env | Set MCP_TIMEOUT |
| mcp-dup-001 | mcp-disable | .mcp.json | Remove duplicate config |
