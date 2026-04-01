---
description: Diagnose and tune your Claude Code setup for maximum effectiveness
argument-hint: [area|all] [--dry-run] [--report-only]
allowed-tools: Bash(cat:*), Bash(wc:*), Bash(jq:*), Bash(mkdir:*), Bash(mv:*), Bash(mktemp:*), Bash(date:*), Read, Glob, Grep, Write, Edit, Agent
---

# /autotune — Claude Code Setup Optimizer

Diagnose and optimize your Claude Code setup across 5 areas: permissions, CLAUDE.md hygiene, model config, plugin health, and MCP servers.

## Arguments

Parse `$ARGUMENTS` for:
- **Area filter**: `permissions`, `claudemd`, `model`, `plugins`, `mcp`, or `all` (default: `all`)
- **Flags**: `--dry-run` (report without fixes), `--report-only` (save report to file)

## Orchestration Flow

### Step 1: Initialize State Directory

```bash
mkdir -p ~/.claude/autotune/findings
```

If `~/.claude/autotune/config.json` doesn't exist, create with defaults:

```json
{
  "version": 1,
  "thresholds": {
    "claudemd_max_lines": 150,
    "claudemd_max_tokens": 5000,
    "hot_files_total_tokens": 15000,
    "stale_run_days": 7,
    "mcp_timeout_ms": 5000,
    "audit_max_entries": 10000
  },
  "enabled_checks": ["permissions", "claudemd", "model", "plugins", "mcp"],
  "auto_apply_severity": "none",
  "best_practices_injected": false
}
```

### Step 2: Read Previous State

Read `~/.claude/autotune/scores.json` and `~/.claude/autotune/findings/*.json` for drift comparison. If no previous state, this is a first run — note it.

### Step 3: Determine Which Agents to Run

Based on area argument and `config.json` enabled_checks:
- `all` → all 5 agents
- specific area → just that agent

### Step 4: Spawn Agents

Dispatch agents using the Agent tool. Rules:
- **Max 4 parallel** (leave 1 subagent slot free)
- If running all 5, launch 4 first, then the 5th when any completes
- Each agent receives: config.json thresholds, previous findings (for comparison)

Agent mapping:
| Area | Agent |
|------|-------|
| permissions | `autotune:permissions-tuner` |
| claudemd | `autotune:claudemd-tuner` |
| model | `autotune:model-tuner` |
| plugins | `autotune:plugin-tuner` |
| mcp | `autotune:mcp-tuner` |

### Step 5: Collect Results

Each agent returns findings[]. If an agent fails or times out:
- Mark area as `"error"` in last-run.json
- Surface failure in report
- Exclude from rules compilation

### Step 6: Consolidate and Report

Sort all findings by severity (critical > warning > info). Present:

```
autotune scan complete

  CRITICAL (N)
    [finding-id] Title
    [finding-id] Title

  WARNING (N)
    [finding-id] Title

  INFO (N)
    [finding-id] Title
```

If `--report-only`: save report to `~/.claude/autotune/report.md` and stop.

### Step 7: Apply Fixes (unless --dry-run)

Present options:
- **all** — apply all fixes in order
- **cherry-pick** — let user select which findings to fix
- **skip** — save report only

For each approved fix:
1. Call the relevant agent to apply the fix
2. Verify fix was applied (idempotency check)
3. Report success/failure

### Step 8: Recompile rules.json

After ALL fixes are applied, compile rules.json atomically:

1. Merge all post-fix findings into a consolidated rule set
2. Write to temp file: `mktemp ~/.claude/autotune/rules.json.XXXXXX`
3. Atomic rename: `mv $TMPFILE ~/.claude/autotune/rules.json`

This ensures hooks enforce the corrected state, not stale pre-fix findings.

### Step 9: Persist State

Update:
- `~/.claude/autotune/last-run.json` — timestamp, status, area results
- `~/.claude/autotune/scores.json` — per-area scores + trend from previous

Score formula: `100 - (critical * 20 + warning * 5 + info * 1)`, clamped 0-100.
Trend: delta from previous score (e.g., `"+5"` = improved by 5 points).

Final output:
```
autotune: score 85/100 (permissions +10, claudemd -5, model stable, plugins +20, mcp stable)
```
