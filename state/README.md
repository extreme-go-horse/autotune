# Autotune State Directory

Runtime state is stored at `~/.claude/autotune/`. This directory is NOT part of the plugin — it's created on first run.

## Layout

```
~/.claude/autotune/
├── config.json          # User preferences (thresholds, enabled checks)
├── last-run.json        # Timestamp + summary of last /autotune
├── findings/            # Per-area finding JSONs
│   ├── permissions.json
│   ├── claudemd.json
│   ├── model.json
│   ├── plugins.json
│   └── mcp.json
├── rules.json           # Compiled rules for hooks (atomic write)
├── audit.jsonl          # Append-only hot file write log
└── scores.json          # Health score per area (0-100) + trend
```

## config.json defaults

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

## rules.json schema

`schema_version: 1`. Hooks check version on invocation — mismatch exits 2.

## Scoring

Score per area: `100 - (critical * 20 + warning * 5 + info * 1)`, clamped 0-100.
Overall: equal-weighted average (v1). Trend: delta from previous run.
