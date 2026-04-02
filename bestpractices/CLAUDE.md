# CLAUDE.md — autotune

Claude Code setup optimizer plugin — diagnose, autotune, and enforce best practices.

## Purpose

Autotune audits a Claude Code environment and provides actionable diagnostics:
- Permissions audit (settings.json correctness, overly permissive configs)
- CLAUDE.md validation (syntax, structure, encoding, `@`-include resolution)
- Plugin health checks (manifest completeness, hook safety, dangling references)
- MCP server diagnostics (discovery, timeout handling, auth validation)
- Shell script safety (Bash 3.2 compat, `set -euo pipefail`, no eval on user input)

## Architecture

Skills-based plugin. No runtime agents in v1 — all functionality exposed as
slash-command skills that run in the caller's session.

```
.claude-plugin/
  plugin.json          # Plugin manifest
  marketplace.json     # Publishing config
docs/
  superpowers/         # Design specs
```

## Conventions

- **Bash 3.2 compatible** — macOS default shell. No bash 4+ features.
- **Shell safety** — `set -euo pipefail`, quoted variables, `mktemp` + trap cleanup.
- **No hardcoded paths** — use `$HOME`, `$XDG_CONFIG_HOME`, or relative paths.
- **No eval on user input** — ever.
- **Diagnostics over fixes** — report problems, let the user decide. Autotune mode is opt-in.

## Testing

### Shell script tests
```bash
bash tests/test-gate-mechanical.sh
bash tests/test-audit-write.sh
bash tests/test-session-health.sh
# Run all:
bash tests/test-gate-mechanical.sh && bash tests/test-audit-write.sh && bash tests/test-session-health.sh
```

### JSON validation
```bash
jq empty .claude-plugin/plugin.json && echo "plugin.json OK"
jq empty hooks/hooks.json && echo "hooks.json OK"
```

### Manual testing (after plugin installed)
```
/autotune              # Full scan of all 5 areas
/autotune permissions  # Single area scan
/autotune --dry-run    # Report without applying fixes
/autotune --report-only # Save report to ~/.claude/autotune/report.md
```

## Dependencies

- **xgh** — shared org infra (dispatch, scheduling, provider scripts)
- **extreme-go-horse org** — CI/CD workflows, labels, quality gates

## Org repos (non-discoverable)

| Repo | Purpose |
|------|---------|
| `extreme-go-horse/autotune` | This repo |
| `extreme-go-horse/xgh` | Shared org infra |
| `ipedro/claudinho` | Org config |
| `ipedro/autoimprove` | Self-improvement loop |
| `lossless-claude/lcm` | Lossless Claude Memory |
