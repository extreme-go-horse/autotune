# Copilot Review Instructions — autotune

This repo implements a Claude Code setup optimizer plugin. It audits environment
permissions, validates CLAUDE.md files, checks plugin health, and diagnoses MCP
server connectivity issues.

## Primary concerns

### Permissions audit correctness (highest priority)
- The audit must have zero false negatives — a misconfigured or overly permissive setting must never pass silently.
- False positives are acceptable but should be minimized — noisy reports erode trust.
- Flag any audit check that inspects a setting without also validating its scope (project vs. global).

### CLAUDE.md validation
- The parser must handle edge cases: empty files, BOM markers, non-UTF8 encoding, deeply nested `@`-includes.
- Structural validation should check for required sections and flag unknown sections as warnings (not errors).
- Path resolution for `@`-includes must be relative to the file's directory, not CWD.

### Plugin health checks
- `plugin.json` must be validated for all required fields (name, version, description).
- Hook safety: `hooks` entries must reference existing files. Flag dangling references.
- Manifest completeness: warn on missing optional but recommended fields (author, license, keywords).

### MCP server diagnostics
- Timeout handling: discovery and health checks must have configurable timeouts with sane defaults.
- Auth validation: check that auth tokens/methods exist before attempting connection.
- Unreachable servers should produce clear diagnostic output, not stack traces.
- Flag any health check that swallows errors silently.

### Bash 3.2 compatibility (macOS default shell)
- No `declare -A` associative arrays (bash 4+).
- No `mapfile` or `readarray` (bash 4+).
- No `&>>` redirect syntax (bash 4+).
- No `[[` with `=~` regex and capture groups via `BASH_REMATCH` — test compatibility.
- Use `#!/usr/bin/env bash` not `#!/bin/bash`.

### Shell safety
- `set -euo pipefail` at the top of every script.
- All `$variables` quoted in commands.
- Temp files use `mktemp` and are cleaned up in a `trap ... EXIT`.
- Never `eval` user-supplied input or file contents.

## What to skip
- Don't flag missing unit tests — the test suite is planned but not yet implemented.
- Don't flag `.yaml` indentation unless it's structurally invalid.
