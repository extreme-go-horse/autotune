# Autotune Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the autotune Claude Code plugin: 5 specialist agents, 3 enforcement shell scripts, hooks configuration, knowledge skill with heuristics, BEST_PRACTICES.md, and the `/autotune` orchestration command.

**Architecture:** Specialist agents diagnose and fix per-subsystem. Shell scripts enforce mechanically (0 tokens). Hooks wire scripts to events. A skill provides semantic knowledge. The `/autotune` command orchestrates the full scan-fix-compile cycle.

**Tech Stack:** Bash 3.2 (macOS compatible), jq, Markdown (agents/skills/commands), JSON (hooks, state schemas)

**Specs:** `docs/superpowers/specs/2026-04-01-autotune-plugin-design.md` and `docs/superpowers/specs/2026-04-01-autotune-best-practices-spec.md`

---

## File Map

### Create

| File | Responsibility |
|------|---------------|
| `agents/permissions-tuner.md` | Diagnose permission settings, promote allow rules |
| `agents/claudemd-tuner.md` | Diagnose CLAUDE.md bloat, inject BEST_PRACTICES.md |
| `agents/model-tuner.md` | Diagnose model/caching config |
| `agents/plugin-tuner.md` | Diagnose plugin health |
| `agents/mcp-tuner.md` | Diagnose MCP server health |
| `hooks/hooks.json` | Wire scripts to PreToolUse, PostToolUse, SessionStart |
| `scripts/gate-mechanical.sh` | Block writes to sensitive/bloated files (exit 2) |
| `scripts/audit-write.sh` | Log hot file writes to audit.jsonl |
| `scripts/session-health.sh` | Quick health check on session start |
| `commands/autotune.md` | `/autotune` orchestration command |
| `skills/autotune-knowledge/SKILL.md` | Semantic knowledge skill |
| `skills/autotune-knowledge/heuristics/permissions.md` | Permission optimization heuristics |
| `skills/autotune-knowledge/heuristics/claudemd.md` | CLAUDE.md hygiene heuristics |
| `skills/autotune-knowledge/heuristics/model-config.md` | Model config heuristics |
| `skills/autotune-knowledge/heuristics/plugins.md` | Plugin health heuristics |
| `skills/autotune-knowledge/heuristics/mcp.md` | MCP server heuristics |
| `skills/autotune-knowledge/references/BEST_PRACTICES.md` | User-facing best practices |
| `state/README.md` | Documents ~/.claude/autotune/ directory layout |
| `tests/test-gate-mechanical.sh` | Tests for gate-mechanical.sh |
| `tests/test-audit-write.sh` | Tests for audit-write.sh |
| `tests/test-session-health.sh` | Tests for session-health.sh |
| `tests/helpers.sh` | Shared test utilities |

### Modify

| File | Change |
|------|--------|
| `.claude-plugin/plugin.json` | Add author object, homepage, repository, keywords |
| `.gitignore` | Add test temp dirs |
| `CLAUDE.md` | Add testing section with actual commands |

## Dependency Graph

```
Task 1 (scaffold) ──┬──> Task 2 (BEST_PRACTICES) ──┐
                     ├──> Task 3 (heuristics)  ──────┤
                     ├──> Task 5 (gate script) ──┐   │
                     ├──> Task 6 (audit script)──┤   │
                     └──> Task 7 (health script)─┤   │
                                                 │   │
                     Task 4 (skill) <────────────┘───┘
                     Task 8 (hooks.json) <───────┘
                                                 
Tasks 9-13 (agents) <── Tasks 3, 4              
Task 14 (command) <──── Tasks 9-13              
Task 15 (integration) < Task 14                 
```

**Parallel groups:**
1. Task 1
2. Tasks 2, 3, 5, 6, 7 (all independent)
3. Tasks 4, 8 (depend on group 2)
4. Tasks 9, 10, 11, 12, 13 (parallel, depend on group 3)
5. Task 14
6. Task 15

---

### Task 1: Plugin Scaffold & State

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Create: `state/README.md`
- Create: `tests/helpers.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Update plugin.json with full metadata**

```json
{
  "name": "autotune",
  "version": "0.1.0",
  "description": "Claude Code setup optimizer — diagnose, autotune, and enforce best practices",
  "author": {
    "name": "Pedro Almeida",
    "url": "https://github.com/ipedro"
  },
  "homepage": "https://github.com/extreme-go-horse/autotune",
  "repository": "https://github.com/extreme-go-horse/autotune",
  "license": "MIT",
  "keywords": ["autotune", "setup", "optimizer", "diagnostics", "best-practices", "claude-code"]
}
```

- [ ] **Step 2: Create state/README.md**

```markdown
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
```

- [ ] **Step 3: Create tests/helpers.sh**

```bash
#!/usr/bin/env bash
# Shared test utilities for autotune shell script tests
# Usage: source tests/helpers.sh

set -euo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (disabled if not tty)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  NC=''
fi

setup_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TEST_TMPDIR"' EXIT
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$actual" -eq "$expected" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (expected exit %d, got %d)\n" "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (output missing: %s)\n" "$label" "$needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (output contains: %s)\n" "$label" "$needle"
  else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (file not found: %s)\n" "$label" "$path"
  fi
}

print_results() {
  echo ""
  echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
  fi
}
```

- [ ] **Step 4: Append to .gitignore**

Add these lines to the existing `.gitignore`:

```
# Test temp dirs
tests/tmp/
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json state/README.md tests/helpers.sh .gitignore
git commit -m "feat: plugin scaffold, state docs, test helpers"
```

---

### Task 2: BEST_PRACTICES.md

**Files:**
- Create: `skills/autotune-knowledge/references/BEST_PRACTICES.md`

**Reference:** `docs/superpowers/specs/2026-04-01-autotune-best-practices-spec.md` section 3

- [ ] **Step 1: Create the file**

```markdown
<!-- autotune:best-practices v1.0.0 -->
# Claude Code Best Practices

## Token Economy
- Sub-agents don't consume parent context — delegate freely, they get their own window
- CLAUDE.md is loaded every turn — every line costs tokens across the entire session
- Use @-includes to keep CLAUDE.md modular; included files are injected every turn, so they still cost tokens — but splitting keeps each file focused and editable
- Prompt caching saves ~80% on repeated context — never disable without a specific reason
- `ctx_execute_file` keeps analysis output in sandbox; `Read` pulls it into your context window
- Compaction quality improves when session memory is fresh — the system uses it as a guide

## Permissions
- Add frequently-approved tools to allow list — each manual approval wastes ~5 seconds + context
- Permission checks happen at execution time, not startup — allow list has zero overhead
- Deny sensitive paths explicitly: .env, secrets/, credentials, *.key files
- Use prefix matching for Bash rules: `Bash(git:*)` covers git status, git diff, git log etc.
- `defaultMode` in settings.json sets the starting permission mode — power users benefit from `acceptEdits`

## Memory
- MEMORY.md is an index (pointers to files), not storage — keep entries under 150 chars each
- Memory recall is model-mediated (LLM selects relevant memories), not keyword search
- Good descriptions matter more than clever names — the model reads descriptions to decide relevance
- Stale memories waste recall budget and can mislead — prune quarterly
- Memory extraction runs in a forked agent with restricted tools — it can't modify your code

## Hooks
- Hooks are snapshotted at startup via captureHooksConfigSnapshot() — mid-session changes don't apply
- Restart Claude Code after modifying hooks for changes to take effect
- PreToolUse hooks can block actions with exit code 2 — use for guardrails
- Keep hook scripts fast (<100ms) — they run on the critical path of every tool execution
- PostToolUse hooks are good for logging and auditing — they don't block the action
- Common events: PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd, PreCompact, PostCompact, Stop, SubagentStop

## Skills vs Commands
- Skills auto-discover by matching task context — use for capabilities the model should find
- Commands require explicit /invoke — use for workflows you trigger manually
- If you repeat the same prompt >3x, it should be a command
- Skill descriptions are critical: include WHAT it does + WHEN to use it with trigger keywords
- Skills can restrict tools via allowed-tools frontmatter — use for read-only or scoped capabilities
- Commands support $ARGUMENTS and positional params ($1, $2) — commands with !`backticks` run bash before the prompt

## MCP Servers
- Set MCP_TIMEOUT for slow-starting servers — default may be too aggressive for heavy servers
- MAX_MCP_OUTPUT_TOKENS defaults to 25000 — raise for data-heavy servers, lower for chatty ones
- Dead MCP servers slow down tool discovery on every session start — prune regularly
- Plugin MCP servers start automatically when the plugin is enabled
- MCP tool permissions use exact match or server-prefix: `mcp__github` (all tools) or `mcp__github__get_issue` (specific) — no wildcards

## Settings
- Precedence (high to low): managed policy > CLI args > local project > shared project > user global
- Settings merge hierarchically — deny rules accumulate across all levels
- Use .claude/settings.local.json for personal project overrides (auto-gitignored)
- Environment variables in settings.json `env` key apply to every session automatically
```

- [ ] **Step 2: Commit**

```bash
git add skills/autotune-knowledge/references/BEST_PRACTICES.md
git commit -m "feat: add BEST_PRACTICES.md reference file (~1030 tokens)"
```

---

### Task 3: Heuristics Files

**Files:**
- Create: `skills/autotune-knowledge/heuristics/permissions.md`
- Create: `skills/autotune-knowledge/heuristics/claudemd.md`
- Create: `skills/autotune-knowledge/heuristics/model-config.md`
- Create: `skills/autotune-knowledge/heuristics/plugins.md`
- Create: `skills/autotune-knowledge/heuristics/mcp.md`

**Source:** Design spec section 4 (agent diagnostics) + best practices spec section 2 (source mapping)

- [ ] **Step 1: Create permissions.md**

```markdown
# Permissions Heuristics

Source: `setup.ts`, `tools.ts`, `Tool.ts`

## Detection Rules

### Critical
- **No deny rules for sensitive paths**: Check settings.json for deny rules matching `.env`, `secrets/`, `credentials`, `*.key`. If absent → finding `perm-sec-001`.
- **Conflicting allow/deny**: Same tool pattern in both allow and deny lists → `perm-conflict-001`.

### Warning
- **Frequently approved but not allowed**: Parse session transcripts (`~/.claude/projects/*/sessions/` JSONL). Count `tool_use` events where tool was manually approved. If tool approved >= 5 times across sessions and not in allow list → `perm-promote-001`.
- **Overly permissive mode**: `defaultMode: "bypassPermissions"` without explicit user intent → `perm-mode-001`.

### Info
- **Prefix matching opportunity**: Multiple individual Bash rules that share a prefix (e.g., `Bash(git status:*)`, `Bash(git diff:*)`) → suggest consolidation to `Bash(git:*)` → `perm-prefix-001`.
- **acceptEdits suggestion**: User has many Edit/Write allow rules but still on `default` mode → suggest `acceptEdits` → `perm-mode-002`.

## Fix Descriptors

| Finding | Fix type | Target | Patch |
|---------|----------|--------|-------|
| perm-sec-001 | settings-merge | settings.json | Add deny rules for sensitive patterns |
| perm-conflict-001 | settings-merge | settings.json | Remove contradicting rule (prefer deny) |
| perm-promote-001 | settings-merge | settings.json | Add tool to allow list |
| perm-mode-001 | settings-merge | settings.json | Change defaultMode (with consent) |
| perm-prefix-001 | settings-merge | settings.json | Replace individual rules with prefix |

## Privacy Gate

Before accessing session transcripts, agent MUST prompt:
> "Autotune wants to analyze session history to optimize permissions. Only tool_use/tool_result events are parsed (not conversation content). Allow?"

Only proceed with transcript analysis if user consents. Skip transcript-dependent findings otherwise.
```

- [ ] **Step 2: Create claudemd.md**

```markdown
# CLAUDE.md Heuristics

Source: `QueryEngine.ts`, `context.ts`

## Detection Rules

### Critical
- **Token budget exceeded**: Estimate tokens as `char_count / 3`. If CLAUDE.md (including resolved @-includes) > `thresholds.claudemd_max_tokens` → `cmd-bloat-001`.
- **Conflicting instructions**: Two lines in CLAUDE.md that contradict each other (requires semantic analysis) → `cmd-conflict-001`.

### Warning
- **Line count exceeded**: CLAUDE.md > `thresholds.claudemd_max_lines` lines → `cmd-lines-001`.
- **Repeated prompt pattern**: Same instruction appears in both global and project CLAUDE.md → `cmd-dup-001`.
- **Content should be skill**: Instruction block that describes a workflow (>5 lines, imperative verbs) → suggest migration to skill → `cmd-skill-001`.
- **Content should be command**: Prompt text that starts with "When I say..." or "When I ask..." → suggest migration to command → `cmd-command-001`.

### Info
- **Missing BEST_PRACTICES.md**: No `@BEST_PRACTICES.md` or `@~/.claude/BEST_PRACTICES.md` include found → `cmd-bp-001`.
- **Hot files total**: Sum token weight of all hot files (CLAUDE.md + settings.json + MEMORY.md + .mcp.json). If > `thresholds.hot_files_total_tokens` → `cmd-hot-001`.

## Token Estimation

Use `char_count / 3` as conservative estimate for markdown-heavy content. `char_count / 4` underestimates by ~30% for code/markup.

## Fix Descriptors

| Finding | Fix type | Target | Patch |
|---------|----------|--------|-------|
| cmd-bloat-001 | suggest | CLAUDE.md | Identify lines to migrate to skills/commands |
| cmd-lines-001 | suggest | CLAUDE.md | Highlight longest sections for compression |
| cmd-dup-001 | edit | CLAUDE.md | Remove duplicate from lower-precedence file |
| cmd-skill-001 | suggest | CLAUDE.md | Propose skill migration with name |
| cmd-bp-001 | inject | CLAUDE.md | Copy BEST_PRACTICES.md to ~/.claude/, add @-include |
| cmd-hot-001 | report | - | Show per-file token breakdown |
```

- [ ] **Step 3: Create model-config.md**

```markdown
# Model Configuration Heuristics

Source: `costHook.ts`, `query.ts`, `cost-tracker.ts`

## Detection Rules

### Critical
- **Caching disabled**: `DISABLE_PROMPT_CACHING=1` in env or settings.json env block → `model-cache-001`. Estimated cost multiplier: 5x.
- **Caching sabotage**: Content pattern `DISABLE_PROMPT_CACHING` being written to any config file → `model-cache-002`.

### Warning
- **No subagent model configured**: `CLAUDE_CODE_SUBAGENT_MODEL` not set. Default uses same model for all agents → `model-subagent-001`. Suggest haiku for lightweight tasks.
- **Thinking tokens unconfigured**: `MAX_THINKING_TOKENS` not set → `model-think-001`. Default may be suboptimal.
- **Output tokens low**: `CLAUDE_CODE_MAX_OUTPUT_TOKENS` set below 16000 → `model-output-001`. Can truncate complex responses.

### Info
- **Heavy MCP + no caching**: MCP servers configured but caching disabled → compound cost flag → `model-compound-001`.

## Environment Variables Checked

| Variable | Default | Effect |
|----------|---------|--------|
| `DISABLE_PROMPT_CACHING` | unset (caching ON) | Setting to 1 disables cache, ~5x cost |
| `MAX_THINKING_TOKENS` | model default | Controls thinking budget |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | 16000 | Max output per response |
| `CLAUDE_CODE_SUBAGENT_MODEL` | same as parent | Model for subagents |

## Fix Descriptors

| Finding | Fix type | Target | Patch |
|---------|----------|--------|-------|
| model-cache-001 | env-remove | settings.json env | Remove DISABLE_PROMPT_CACHING |
| model-subagent-001 | env-set | settings.json env | Set CLAUDE_CODE_SUBAGENT_MODEL |
| model-think-001 | suggest | settings.json env | Recommend MAX_THINKING_TOKENS value |
| model-output-001 | env-set | settings.json env | Raise CLAUDE_CODE_MAX_OUTPUT_TOKENS |
```

- [ ] **Step 4: Create plugins.md**

```markdown
# Plugin Health Heuristics

Source: `utils/plugins/pluginLoader.ts`

## Detection Rules

### Critical
- **Ghost plugin**: Plugin listed in settings but directory missing or manifest invalid → `plug-ghost-001`.
- **Namespace conflict**: Two plugins register commands/agents with same name → `plug-ns-001`.

### Warning
- **Duplicate plugin**: Same plugin name appears from multiple sources (local + marketplace) → `plug-dup-001`.
- **Outdated manifest**: plugin.json missing required fields (name) or has invalid version → `plug-manifest-001`.
- **Hook conflict**: Two plugins register hooks on same event+matcher that could interfere → `plug-hook-001`.

### Info
- **Plugin count**: More than 10 plugins installed → `plug-count-001`. Each adds startup overhead.
- **Unused plugin**: Plugin installed but no commands/agents/skills used in recent sessions → `plug-unused-001` (requires transcript access).

## Detection Method

1. List plugins from `~/.claude/settings.json` `plugins` array
2. For each plugin path, validate:
   - Directory exists
   - `.claude-plugin/plugin.json` exists and is valid JSON
   - `name` field present and non-empty
3. Cross-reference: collect all command names, agent names across plugins → detect duplicates
4. Check hooks: parse each plugin's hooks.json → detect overlapping event+matcher pairs

## Fix Descriptors

| Finding | Fix type | Target | Patch |
|---------|----------|--------|-------|
| plug-ghost-001 | settings-merge | settings.json | Remove dead plugin reference |
| plug-ns-001 | report | - | Show conflicting plugins, user decides |
| plug-dup-001 | settings-merge | settings.json | Remove duplicate (keep preferred source) |
| plug-manifest-001 | report | - | Show what's missing |
```

- [ ] **Step 5: Create mcp.md**

```markdown
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
```

- [ ] **Step 6: Commit**

```bash
git add skills/autotune-knowledge/heuristics/
git commit -m "feat: add heuristic files for all 5 diagnostic areas"
```

---

### Task 4: Autotune Knowledge Skill

**Files:**
- Create: `skills/autotune-knowledge/SKILL.md`

- [ ] **Step 1: Create SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add skills/autotune-knowledge/SKILL.md
git commit -m "feat: add autotune-knowledge skill with heuristic references"
```

---

### Task 5: Gate Mechanical Script + Tests

**Files:**
- Create: `scripts/gate-mechanical.sh`
- Create: `tests/test-gate-mechanical.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Tests for gate-mechanical.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

GATE="$SCRIPT_DIR/../scripts/gate-mechanical.sh"

# Create a minimal rules.json for tests
RULES_DIR="$TEST_TMPDIR/autotune"
mkdir -p "$RULES_DIR"
cat > "$RULES_DIR/rules.json" << 'RULES'
{
  "schema_version": 1,
  "compiled_at": "2026-04-01T00:00:00Z",
  "hot_files": ["CLAUDE.md", "settings.json"],
  "block_rules": [
    {"pattern": "\\.env(\\..+)?$", "reason": "Sensitive file"},
    {"pattern": "credentials", "reason": "Credentials file"},
    {"pattern": "secrets/", "reason": "Secrets directory"},
    {"pattern": "DISABLE_PROMPT_CACHING", "reason": "Caching sabotage"}
  ],
  "warn_rules": [
    {"file": "CLAUDE.md", "max_lines": 10}
  ]
}
RULES

# Create a small CLAUDE.md for line count tests
printf 'line1\nline2\nline3\n' > "$TEST_TMPDIR/CLAUDE.md"

# --- Test: normal file passes ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "normal file passes"

# --- Test: .env file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/.env","content":"SECRET=123"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env file blocked"
assert_contains "$OUTPUT" "Sensitive file" ".env block message"

# --- Test: .env.local file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/.env.local","content":"SECRET=123"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env.local file blocked"

# --- Test: .env.production blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/project/.env.production","content":"x"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env.production blocked"

# --- Test: credentials file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/credentials.json","content":"{}"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "credentials file blocked"

# --- Test: secrets/ directory blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/project/secrets/key.pem","content":"-----"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "secrets/ directory blocked"

# --- Test: caching sabotage blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/.claude/settings.json","content":"DISABLE_PROMPT_CACHING=1"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "caching sabotage blocked"
assert_contains "$OUTPUT" "Caching sabotage" "caching sabotage message"

# --- Test: missing rules.json passes (no rules = no blocks) ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "missing rules.json passes gracefully"

# --- Test: wrong schema version blocks ---
mkdir -p "$TEST_TMPDIR/bad_rules"
cat > "$TEST_TMPDIR/bad_rules/rules.json" << 'RULES'
{"schema_version": 99}
RULES
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/bad_rules" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "wrong schema version blocks"
assert_contains "$OUTPUT" "schema mismatch" "schema mismatch message"

# --- Test: envfile.txt not blocked (env in middle of name) ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/envfile.txt","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "envfile.txt not blocked (false positive check)"

print_results
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-gate-mechanical.sh
bash tests/test-gate-mechanical.sh
```

Expected: FAIL (gate-mechanical.sh doesn't exist yet)

- [ ] **Step 3: Implement gate-mechanical.sh**

```bash
#!/usr/bin/env bash
# gate-mechanical.sh — PreToolUse Write/Edit guard
# Reads rules.json, blocks writes to sensitive/bloated files
# Exit 0 = allow, Exit 2 = block (message on stderr)
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"

# No rules file = no enforcement (first run before /autotune)
if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

# Read input from stdin
INPUT=$(cat)

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  exit 0  # No jq = can't enforce, allow through
fi

# Validate schema version
SCHEMA_VERSION=$(jq -r '.schema_version // 0' "$RULES_FILE" 2>/dev/null) || SCHEMA_VERSION=0
if [ "$SCHEMA_VERSION" != "1" ]; then
  echo "autotune: rules.json schema mismatch (got v${SCHEMA_VERSION}, expected v1) — run \`/autotune\` to recompile" >&2
  exit 2
fi

# Extract file path and content from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null) || CONTENT=""

if [ -z "$FILE_PATH" ]; then
  exit 0  # No file path = not a file write, allow
fi

# Check block rules against file path
BLOCK_COUNT=$(jq -r '.block_rules | length' "$RULES_FILE" 2>/dev/null) || BLOCK_COUNT=0
i=0
while [ "$i" -lt "$BLOCK_COUNT" ]; do
  PATTERN=$(jq -r ".block_rules[$i].pattern" "$RULES_FILE")
  REASON=$(jq -r ".block_rules[$i].reason" "$RULES_FILE")

  # Check file path against pattern
  if echo "$FILE_PATH" | grep -qE "$PATTERN"; then
    echo "autotune: BLOCKED — $REASON (matched: $FILE_PATH)" >&2
    exit 2
  fi

  # Check content against pattern (for sabotage detection)
  if [ -n "$CONTENT" ] && echo "$CONTENT" | grep -qE "$PATTERN"; then
    echo "autotune: BLOCKED — $REASON (content match in $FILE_PATH)" >&2
    exit 2
  fi

  i=$((i + 1))
done

exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/gate-mechanical.sh
bash tests/test-gate-mechanical.sh
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/gate-mechanical.sh tests/test-gate-mechanical.sh
git commit -m "feat: gate-mechanical.sh with block rules enforcement + tests"
```

---

### Task 6: Audit Write Script + Tests

**Files:**
- Create: `scripts/audit-write.sh`
- Create: `tests/test-audit-write.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Tests for audit-write.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

AUDIT="$SCRIPT_DIR/../scripts/audit-write.sh"

# Create state dir
STATE_DIR="$TEST_TMPDIR/autotune"
mkdir -p "$STATE_DIR"

# Create rules.json with hot_files
cat > "$STATE_DIR/rules.json" << 'RULES'
{
  "schema_version": 1,
  "hot_files": ["CLAUDE.md", "settings.json", "MEMORY.md"],
  "block_rules": [],
  "warn_rules": []
}
RULES

# Create config.json with audit_max_entries
cat > "$STATE_DIR/config.json" << 'CONFIG'
{
  "version": 1,
  "thresholds": { "audit_max_entries": 5 }
}
CONFIG

# --- Test: hot file write is logged ---
echo '{"tool_input":{"file_path":"/home/user/.claude/CLAUDE.md","content":"line1\nline2\nline3"}}' | \
  AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
assert_file_exists "$STATE_DIR/audit.jsonl" "audit.jsonl created"
LAST_LINE=$(tail -1 "$STATE_DIR/audit.jsonl")
assert_contains "$LAST_LINE" "CLAUDE.md" "audit entry contains filename"
assert_contains "$LAST_LINE" '"action":"edit"' "audit entry has action"

# --- Test: non-hot file is NOT logged ---
BEFORE=$(wc -l < "$STATE_DIR/audit.jsonl")
echo '{"tool_input":{"file_path":"/tmp/random.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
AFTER=$(wc -l < "$STATE_DIR/audit.jsonl")
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$BEFORE" -eq "$AFTER" ]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} non-hot file not logged\n"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC} non-hot file was logged\n"
fi

# --- Test: rotation at max entries ---
for i in 1 2 3 4 5 6; do
  echo "{\"tool_input\":{\"file_path\":\"/home/.claude/CLAUDE.md\",\"content\":\"line$i\"}}" | \
    AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
done
LINE_COUNT=$(wc -l < "$STATE_DIR/audit.jsonl")
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$LINE_COUNT" -le 5 ]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} audit rotation works (lines: %d <= 5)\n" "$LINE_COUNT"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC} audit rotation failed (lines: %d > 5)\n" "$LINE_COUNT"
fi

# --- Test: missing rules.json = no logging ---
echo '{"tool_input":{"file_path":"/home/.claude/CLAUDE.md","content":"x"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$AUDIT" 2>/dev/null || CODE=$?
CODE=${CODE:-0}
assert_exit_code 0 "$CODE" "missing rules.json exits cleanly"

print_results
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-audit-write.sh
bash tests/test-audit-write.sh
```

Expected: FAIL

- [ ] **Step 3: Implement audit-write.sh**

```bash
#!/usr/bin/env bash
# audit-write.sh — PostToolUse Write/Edit logger
# Appends to audit.jsonl when hot files are modified
# Always exits 0 (never blocks — this is post-action)
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"
AUDIT_FILE="$AUTOTUNE_STATE_DIR/audit.jsonl"
CONFIG_FILE="$AUTOTUNE_STATE_DIR/config.json"

# No rules = no hot file list = nothing to log
if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Read input
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Extract just the filename for matching
FILENAME=$(basename "$FILE_PATH")

# Check if this is a hot file
IS_HOT=$(jq -r --arg name "$FILENAME" '.hot_files[]? | select(. == $name)' "$RULES_FILE" 2>/dev/null) || IS_HOT=""

if [ -z "$IS_HOT" ]; then
  exit 0  # Not a hot file, skip
fi

# Calculate content metrics
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null) || CONTENT=""
if [ -n "$CONTENT" ]; then
  LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
  CHAR_COUNT=${#CONTENT}
  TOKEN_ESTIMATE=$((CHAR_COUNT / 3))
else
  LINE_COUNT=0
  CHAR_COUNT=0
  TOKEN_ESTIMATE=0
fi

# Get timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create state dir if needed
mkdir -p "$AUTOTUNE_STATE_DIR"

# Append audit entry
printf '{"ts":"%s","file":"%s","action":"edit","lines":%d,"chars":%d,"token_estimate":%d}\n' \
  "$TS" "$FILE_PATH" "$LINE_COUNT" "$CHAR_COUNT" "$TOKEN_ESTIMATE" >> "$AUDIT_FILE"

# Rotation check
MAX_ENTRIES=10000
if [ -f "$CONFIG_FILE" ]; then
  MAX_ENTRIES=$(jq -r '.thresholds.audit_max_entries // 10000' "$CONFIG_FILE" 2>/dev/null) || MAX_ENTRIES=10000
fi

CURRENT_LINES=$(wc -l < "$AUDIT_FILE" | tr -d ' ')
if [ "$CURRENT_LINES" -gt "$MAX_ENTRIES" ]; then
  # Keep newest 50%
  KEEP=$((MAX_ENTRIES / 2))
  TAIL_TMP=$(mktemp)
  tail -n "$KEEP" "$AUDIT_FILE" > "$TAIL_TMP"
  mv "$TAIL_TMP" "$AUDIT_FILE"
fi

exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/audit-write.sh
bash tests/test-audit-write.sh
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/audit-write.sh tests/test-audit-write.sh
git commit -m "feat: audit-write.sh with hot file logging + rotation + tests"
```

---

### Task 7: Session Health Script + Tests

**Files:**
- Create: `scripts/session-health.sh`
- Create: `tests/test-session-health.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Tests for session-health.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

HEALTH="$SCRIPT_DIR/../scripts/session-health.sh"

# --- Test: healthy state ---
STATE_DIR="$TEST_TMPDIR/healthy"
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/rules.json" << 'RULES'
{"schema_version": 1, "hot_files": [], "block_rules": [], "warn_rules": []}
RULES
cat > "$STATE_DIR/last-run.json" << LASTRUN
{"timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")", "status": "ok"}
LASTRUN
cat > "$STATE_DIR/scores.json" << 'SCORES'
{"overall": 85, "areas": {}}
SCORES

OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
CODE=${CODE:-0}
assert_exit_code 0 "$CODE" "healthy state exits 0"
assert_contains "$OUTPUT" "autotune" "output mentions autotune"

# --- Test: stale run warning ---
STATE_DIR="$TEST_TMPDIR/stale"
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/rules.json" << 'RULES'
{"schema_version": 1, "hot_files": [], "block_rules": [], "warn_rules": []}
RULES
cat > "$STATE_DIR/last-run.json" << 'LASTRUN'
{"timestamp": "2025-01-01T00:00:00Z", "status": "ok"}
LASTRUN
cat > "$STATE_DIR/config.json" << 'CONFIG'
{"version": 1, "thresholds": {"stale_run_days": 7}}
CONFIG

OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
CODE=${CODE:-0}
assert_exit_code 0 "$CODE" "stale run still exits 0"
assert_contains "$OUTPUT" "stale" "stale warning shown"

# --- Test: missing state dir = first run ---
OUTPUT=$(AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$HEALTH" 2>&1) || CODE=$?
CODE=${CODE:-0}
assert_exit_code 0 "$CODE" "missing state dir exits 0"
assert_contains "$OUTPUT" "autotune" "first run message shown"

# --- Test: broken rules.json ---
STATE_DIR="$TEST_TMPDIR/broken"
mkdir -p "$STATE_DIR"
echo "not json" > "$STATE_DIR/rules.json"

OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
CODE=${CODE:-0}
assert_exit_code 0 "$CODE" "broken rules.json exits 0"
assert_contains "$OUTPUT" "warning" "broken rules warning shown"

print_results
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-session-health.sh
bash tests/test-session-health.sh
```

Expected: FAIL

- [ ] **Step 3: Implement session-health.sh**

```bash
#!/usr/bin/env bash
# session-health.sh — SessionStart quick health check
# Reports autotune status line. Always exits 0 (never blocks session start).
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"
LASTRUN_FILE="$AUTOTUNE_STATE_DIR/last-run.json"
SCORES_FILE="$AUTOTUNE_STATE_DIR/scores.json"
CONFIG_FILE="$AUTOTUNE_STATE_DIR/config.json"

WARNINGS=0
MESSAGES=""

add_warning() {
  WARNINGS=$((WARNINGS + 1))
  if [ -n "$MESSAGES" ]; then
    MESSAGES="$MESSAGES, $1"
  else
    MESSAGES="$1"
  fi
}

# Check if state dir exists (first run?)
if [ ! -d "$AUTOTUNE_STATE_DIR" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"autotune: not configured — run `/autotune` for first setup"}}'
  exit 0
fi

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"autotune: jq not found — install jq for full diagnostics"}}'
  exit 0
fi

# Check rules.json integrity
if [ -f "$RULES_FILE" ]; then
  if ! jq empty "$RULES_FILE" 2>/dev/null; then
    add_warning "rules.json corrupted"
  fi
else
  add_warning "no rules.json"
fi

# Check stale run
STALE_DAYS=7
if [ -f "$CONFIG_FILE" ]; then
  STALE_DAYS=$(jq -r '.thresholds.stale_run_days // 7' "$CONFIG_FILE" 2>/dev/null) || STALE_DAYS=7
fi

if [ -f "$LASTRUN_FILE" ]; then
  LAST_TS=$(jq -r '.timestamp // empty' "$LASTRUN_FILE" 2>/dev/null) || LAST_TS=""
  if [ -n "$LAST_TS" ]; then
    # Calculate days since last run (portable: use date comparison)
    if command -v python3 >/dev/null 2>&1; then
      DAYS_AGO=$(python3 -c "
from datetime import datetime, timezone
try:
    ts = datetime.fromisoformat('$LAST_TS'.replace('Z', '+00:00'))
    delta = datetime.now(timezone.utc) - ts
    print(delta.days)
except:
    print(999)
" 2>/dev/null) || DAYS_AGO=999
    else
      DAYS_AGO=0  # Can't check without python3
    fi
    if [ "$DAYS_AGO" -gt "$STALE_DAYS" ]; then
      add_warning "stale (last run ${DAYS_AGO}d ago)"
    fi
  fi
else
  add_warning "never run"
fi

# Get score
SCORE=""
if [ -f "$SCORES_FILE" ]; then
  SCORE=$(jq -r '.overall // empty' "$SCORES_FILE" 2>/dev/null) || SCORE=""
fi

# Build status line
if [ "$WARNINGS" -gt 0 ]; then
  if [ -n "$SCORE" ]; then
    STATUS="autotune: ${SCORE}/100 — ${WARNINGS} warning(s): ${MESSAGES}"
  else
    STATUS="autotune: ${WARNINGS} warning(s): ${MESSAGES}"
  fi
else
  if [ -n "$SCORE" ]; then
    STATUS="autotune: ${SCORE}/100 — healthy"
  else
    STATUS="autotune: healthy"
  fi
fi

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$STATUS\"}}"
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/session-health.sh
bash tests/test-session-health.sh
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/session-health.sh tests/test-session-health.sh
git commit -m "feat: session-health.sh with stale run detection + integrity checks + tests"
```

---

### Task 8: Hooks Configuration

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Create hooks.json**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gate-mechanical.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/audit-write.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-health.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

```bash
jq empty hooks/hooks.json && echo "valid JSON"
```

Expected: "valid JSON"

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: hooks.json wiring scripts to PreToolUse, PostToolUse, SessionStart"
```

---

### Task 9: Permissions Tuner Agent

**Files:**
- Create: `agents/permissions-tuner.md`

- [ ] **Step 1: Create the agent**

```markdown
---
name: permissions-tuner
description: Diagnose and optimize Claude Code permission settings. Use when auditing settings.json allow/deny rules, detecting missing sensitive path protections, or promoting frequently-approved tools. Invoked by the /autotune command or manually when permission friction is high.
tools: Read, Grep, Glob, Write, Edit, Bash(jq:*), Bash(wc:*), Bash(cat:*)
---

# Permissions Tuner

Specialist agent for Claude Code permission optimization. Scans settings.json at all levels, analyzes session transcripts (with consent), and produces actionable findings.

## Contract

1. **Scan** — read settings.json (global, project, local), optionally analyze session transcripts
2. **Report** — produce findings[] with severity (critical/warning/info) and stable IDs
3. **Fix** — apply fixes with user consent, all idempotent
4. **Persist** — save findings to `~/.claude/autotune/findings/permissions.json`

## Scan Procedure

### Step 1: Read Settings

Read these files (skip if not found):
- `~/.claude/settings.json` (global)
- `.claude/settings.json` (project shared)
- `.claude/settings.local.json` (project local)

Extract: `permissions.allow[]`, `permissions.deny[]`, `permissions.defaultMode`

### Step 2: Check Sensitive Path Protection

Verify deny rules exist for these patterns. If missing, emit finding:
- `.env` files: pattern `\.env(\..+)?$`
- `secrets/` directory
- `credentials` files
- `*.key` files

Finding ID: `perm-sec-001` (critical)

### Step 3: Check Conflicting Rules

Compare allow and deny lists. Same tool pattern in both = conflict.

Finding ID: `perm-conflict-001` (critical)

### Step 4: Transcript Analysis (requires consent)

**Before accessing transcripts, ask:**
> "Autotune wants to analyze session history to optimize permissions. Only tool_use/tool_result events are parsed (not conversation content). Allow?"

If allowed:
- Read JSONL files from `~/.claude/projects/*/sessions/`
- Count tool approvals per tool name
- If tool approved >= 5 times and not in allow list → finding

Finding ID: `perm-promote-001` (warning)

If denied: skip transcript findings, note in report.

### Step 5: Check Permission Mode

- `bypassPermissions` without explicit user intent → `perm-mode-001` (warning)
- Many Edit/Write allows but still on `default` → suggest `acceptEdits` → `perm-mode-002` (info)

### Step 6: Check Prefix Consolidation

Multiple Bash rules sharing prefix (e.g., `Bash(git status:*)`, `Bash(git diff:*)`) → suggest `Bash(git:*)`.

Finding ID: `perm-prefix-001` (info)

## Output Format

Return findings as JSON array. Each finding:

```json
{
  "id": "perm-xxx-NNN",
  "area": "permissions",
  "severity": "critical|warning|info",
  "title": "Short description",
  "description": "Detailed explanation with impact",
  "fix": {
    "type": "settings-merge",
    "target": "~/.claude/settings.json",
    "patch": {}
  },
  "idempotent": true
}
```

## Persistence

Save findings to `~/.claude/autotune/findings/permissions.json`:

```json
{
  "area": "permissions",
  "timestamp": "ISO-8601",
  "findings": [...],
  "score": 0-100
}
```

Score: `100 - (critical * 20 + warning * 5 + info * 1)`, clamped 0-100.

## Fix Application

For each fix the user approves:
1. Read current settings.json
2. Check if fix already applied (idempotency check)
3. Apply patch (merge arrays, set values)
4. Write back with proper JSON formatting
5. Report what changed
```

- [ ] **Step 2: Commit**

```bash
git add agents/permissions-tuner.md
git commit -m "feat: permissions-tuner agent — settings audit + transcript analysis"
```

---

### Task 10: CLAUDE.md Tuner Agent

**Files:**
- Create: `agents/claudemd-tuner.md`

- [ ] **Step 1: Create the agent**

```markdown
---
name: claudemd-tuner
description: Diagnose and optimize CLAUDE.md files for token efficiency. Use when auditing CLAUDE.md bloat, detecting redundant instructions, migrating content to skills/commands, or injecting BEST_PRACTICES.md. Invoked by the /autotune command or manually when CLAUDE.md grows large.
tools: Read, Grep, Glob, Write, Edit, Bash(wc:*), Bash(cat:*)
---

# CLAUDE.md Tuner

Specialist agent for CLAUDE.md hygiene and token optimization. Measures token weight of hot files, detects bloat and redundancy, and manages BEST_PRACTICES.md injection.

## Contract

1. **Scan** — measure token weight, detect patterns, cross-reference files
2. **Report** — produce findings[] with stable IDs
3. **Fix** — apply with consent, idempotent
4. **Persist** — save to `~/.claude/autotune/findings/claudemd.json`

## Scan Procedure

### Step 1: Measure Hot Files

Read and measure token weight (chars / 3) for each hot file:
- `~/.claude/CLAUDE.md` (global)
- `.claude/CLAUDE.md` (project shared, if in a project)
- `~/.claude/settings.json`
- `~/.claude/MEMORY.md`

Resolve `@`-includes: for each `@path` line, read the included file and add its weight.

### Step 2: Check CLAUDE.md Size

- Line count > `thresholds.claudemd_max_lines` (default 150) → `cmd-lines-001` (warning)
- Token weight > `thresholds.claudemd_max_tokens` (default 5000) → `cmd-bloat-001` (critical)
- Total hot files > `thresholds.hot_files_total_tokens` (default 15000) → `cmd-hot-001` (info)

### Step 3: Detect Redundancy

- Same instruction in global and project CLAUDE.md → `cmd-dup-001` (warning)
- Overlap between CLAUDE.md and MEMORY.md content → `cmd-dup-002` (info)

### Step 4: Detect Migration Candidates

- Instruction block > 5 lines with imperative verbs ("always", "never", "when") → suggest skill → `cmd-skill-001` (warning)
- Pattern "When I say..." or "When I ask..." → suggest command → `cmd-command-001` (warning)

### Step 5: Check BEST_PRACTICES.md

- No `@BEST_PRACTICES.md` or `@~/.claude/BEST_PRACTICES.md` in any CLAUDE.md → `cmd-bp-001` (info)

## BEST_PRACTICES.md Injection

When fixing `cmd-bp-001`:

1. Check if `~/.claude/BEST_PRACTICES.md` already exists
2. If not, copy from plugin: `${CLAUDE_PLUGIN_ROOT}/skills/autotune-knowledge/references/BEST_PRACTICES.md` to `~/.claude/BEST_PRACTICES.md`
3. Show the user what will be added to context (the full BEST_PRACTICES.md content)
4. With consent, add `@BEST_PRACTICES.md` line to `~/.claude/CLAUDE.md`
5. Set `best_practices_injected: true` in `~/.claude/autotune/config.json`

**Idempotency**: if `@BEST_PRACTICES.md` or `@~/.claude/BEST_PRACTICES.md` already in CLAUDE.md → skip.

**Version check**: compare version comment in installed vs user copy. If plugin version newer → propose update.

## Output Format

Same as permissions-tuner: JSON array of findings with standard schema.

Fix types:
- `edit` — modify CLAUDE.md directly (remove duplicate lines)
- `inject` — add @-include for BEST_PRACTICES.md
- `suggest` — recommend migration to skill/command (user does manually)
- `report` — show token breakdown (no automatic fix)

## Persistence

Save to `~/.claude/autotune/findings/claudemd.json` with same schema as permissions-tuner.
```

- [ ] **Step 2: Commit**

```bash
git add agents/claudemd-tuner.md
git commit -m "feat: claudemd-tuner agent — token hygiene + BEST_PRACTICES injection"
```

---

### Task 11: Model Tuner Agent

**Files:**
- Create: `agents/model-tuner.md`

- [ ] **Step 1: Create the agent**

```markdown
---
name: model-tuner
description: Diagnose and optimize Claude Code model configuration and caching. Use when auditing prompt caching settings, thinking token budgets, output limits, or subagent model selection. Invoked by the /autotune command or manually when cost seems high.
tools: Read, Grep, Glob, Write, Edit, Bash(jq:*), Bash(cat:*)
---

# Model Tuner

Specialist agent for model configuration and cost optimization. Checks caching, thinking tokens, output limits, and subagent model settings.

## Contract

1. **Scan** — read settings.json env blocks, check environment variables
2. **Report** — produce findings[] with stable IDs and cost impact estimates
3. **Fix** — apply with consent, idempotent
4. **Persist** — save to `~/.claude/autotune/findings/model.json`

## Scan Procedure

### Step 1: Check Prompt Caching

Read `settings.json` (all levels) for `env.DISABLE_PROMPT_CACHING`.

- If set to `"1"` or `"true"` → `model-cache-001` (critical)
  - Impact: "Disabling prompt caching increases cost by ~5x. Estimated +$2-5/day for active users."

### Step 2: Check Subagent Model

Read `env.CLAUDE_CODE_SUBAGENT_MODEL`.

- If not set → `model-subagent-001` (warning)
  - Suggestion: "Set to `claude-haiku-4-5-20251001` for lightweight subagent tasks (research, file search). Saves ~70% on subagent cost."

### Step 3: Check Thinking Tokens

Read `env.MAX_THINKING_TOKENS`.

- If not set → `model-think-001` (warning)
  - Note: "Default may be suboptimal. Consider setting based on work type: 8000 for standard coding, 16000 for complex architecture."

### Step 4: Check Output Limits

Read `env.CLAUDE_CODE_MAX_OUTPUT_TOKENS`.

- If set and < 16000 → `model-output-001` (warning)
  - Impact: "Low output limit can truncate complex code generation and long explanations."

### Step 5: Cross-Check Compound Issues

- MCP servers configured + caching disabled → `model-compound-001` (info)
  - Note: "MCP tool results aren't cached. Combined with disabled caching, every turn is fully billed."

## Output Format

Same standard finding schema. Fix type: `env-set` (add/modify env var in settings.json) or `env-remove` (remove env var).

## Persistence

Save to `~/.claude/autotune/findings/model.json`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/model-tuner.md
git commit -m "feat: model-tuner agent — caching, thinking tokens, cost optimization"
```

---

### Task 12: Plugin Tuner Agent

**Files:**
- Create: `agents/plugin-tuner.md`

- [ ] **Step 1: Create the agent**

```markdown
---
name: plugin-tuner
description: Diagnose Claude Code plugin health. Use when auditing installed plugins for ghost references, namespace conflicts, duplicate installations, or invalid manifests. Invoked by the /autotune command or manually when plugins misbehave.
tools: Read, Grep, Glob, Bash(jq:*), Bash(ls:*), Bash(cat:*)
---

# Plugin Tuner

Specialist agent for plugin ecosystem health. Validates all installed plugins, detects conflicts, and cleans up dead references.

## Contract

1. **Scan** — enumerate plugins, validate manifests, check for conflicts
2. **Report** — produce findings[] with stable IDs
3. **Fix** — apply with consent, idempotent
4. **Persist** — save to `~/.claude/autotune/findings/plugins.json`

## Scan Procedure

### Step 1: Enumerate Plugins

Read plugin sources:
- `~/.claude/settings.json` → `plugins` array (local plugin paths)
- `~/.claude/plugins/cache/` → marketplace plugins (auto-discovered)

For each plugin path, check:
- Directory exists → if not, `plug-ghost-001` (critical)
- `.claude-plugin/plugin.json` exists → if not, `plug-ghost-001`
- plugin.json is valid JSON with `name` field → if not, `plug-manifest-001` (warning)

### Step 2: Check Duplicates

Collect all plugin names. If same name appears from multiple sources → `plug-dup-001` (warning).

### Step 3: Check Namespace Conflicts

Collect all command names (from `commands/` dirs) and agent names (from `agents/` dirs) across all plugins. If duplicate name found → `plug-ns-001` (critical).

### Step 4: Check Hook Conflicts

For each plugin with hooks:
- Parse hooks.json
- Collect event+matcher pairs
- If two plugins register hooks on same event+matcher → `plug-hook-001` (warning)

### Step 5: Plugin Count

- More than 10 plugins → `plug-count-001` (info)
  - Note: "Each plugin adds startup overhead. Consider disabling unused plugins."

## Output Format

Standard finding schema. Fix types:
- `settings-merge` — remove dead plugin reference from settings.json
- `report` — show conflicts (user decides which plugin to keep)

## Persistence

Save to `~/.claude/autotune/findings/plugins.json`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/plugin-tuner.md
git commit -m "feat: plugin-tuner agent — ghost detection, namespace conflicts, manifest validation"
```

---

### Task 13: MCP Tuner Agent

**Files:**
- Create: `agents/mcp-tuner.md`

- [ ] **Step 1: Create the agent**

```markdown
---
name: mcp-tuner
description: Diagnose MCP server health and configuration. Use when auditing MCP servers for dead connections, slow response times, timeout misconfigurations, or duplicate servers. Invoked by the /autotune command or manually when MCP tools are slow or missing.
tools: Read, Grep, Glob, Bash(jq:*), Bash(cat:*), Bash(ls:*)
---

# MCP Tuner

Specialist agent for MCP server health and configuration optimization. Pings servers, measures response times, and validates timeout settings.

## Contract

1. **Scan** — read .mcp.json configs, health-check servers, validate timeouts
2. **Report** — produce findings[] with stable IDs
3. **Fix** — apply with consent, idempotent
4. **Persist** — save to `~/.claude/autotune/findings/mcp.json`

## Scan Procedure

### Step 1: Read MCP Configuration

Read `.mcp.json` from:
- `~/.claude/.mcp.json` (global)
- `.mcp.json` (project-level)

Collect all server entries with their command, args, and env.

### Step 2: Health Check Servers

For each server, attempt a basic connectivity check:
- Parse the server command to understand what type it is
- Check if the command binary exists (e.g., `which npx`, `which node`)
- If server has a known health endpoint or can be pinged, do so

Timeout per server: `thresholds.mcp_timeout_ms` (default 5000ms). Total cap: 5 seconds for all servers combined. Run checks in parallel where possible.

- Server command binary missing → `mcp-dead-001` (critical)
- Server doesn't respond within timeout → `mcp-dead-001` (critical)
- Server responds but > 2000ms → `mcp-slow-001` (warning)

### Step 3: Check Timeout Configuration

- `MCP_TIMEOUT` not set and any server > 1000ms → `mcp-timeout-001` (warning)
- `MAX_MCP_OUTPUT_TOKENS` at default (25000) with data-heavy servers → `mcp-output-001` (warning)

### Step 4: Check Duplicates

Two server configs with identical command+args → `mcp-dup-001` (warning).

### Step 5: Server Count

- More than 5 MCP servers → `mcp-count-001` (info)
  - Note: "Each server adds discovery overhead at session start."

## Output Format

Standard finding schema. Fix types:
- `mcp-disable` — remove/comment out dead server in .mcp.json
- `env-set` — set MCP_TIMEOUT in settings.json env
- `report` — show server health matrix

## Health Matrix Output

When reporting, include a table:

```
MCP Server Health:
  context-mode  ✅ 120ms
  github        ✅ 340ms
  slack         ❌ timeout (5000ms)
  telegram      ⚠️ slow (2100ms)
```

## Persistence

Save to `~/.claude/autotune/findings/mcp.json`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/mcp-tuner.md
git commit -m "feat: mcp-tuner agent — server health, timeout config, duplicate detection"
```

---

### Task 14: `/autotune` Command

**Files:**
- Create: `commands/autotune.md`

- [ ] **Step 1: Create the command**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/autotune.md
git commit -m "feat: /autotune command — orchestration flow with 9-step scan-fix-compile cycle"
```

---

### Task 15: Integration & Local Install

**Files:**
- Modify: `CLAUDE.md` (update testing section)

- [ ] **Step 1: Run all shell script tests**

```bash
bash tests/test-gate-mechanical.sh && \
bash tests/test-audit-write.sh && \
bash tests/test-session-health.sh
```

Expected: all PASS

- [ ] **Step 2: Validate all JSON files**

```bash
jq empty .claude-plugin/plugin.json && echo "plugin.json OK"
jq empty hooks/hooks.json && echo "hooks.json OK"
```

Expected: both OK

- [ ] **Step 3: Verify directory structure matches spec**

```bash
ls -la agents/ commands/ hooks/ scripts/ skills/autotune-knowledge/ skills/autotune-knowledge/heuristics/ skills/autotune-knowledge/references/ state/ tests/
```

Expected: all directories exist with expected files

- [ ] **Step 4: Install plugin locally for testing**

Use the `install-local-plugin` skill to install the plugin from the current directory. This registers the plugin in `~/.claude/settings.json`.

- [ ] **Step 5: Verify plugin loads**

```bash
claude --debug 2>&1 | head -20
```

Check that autotune plugin appears in loaded plugins list.

- [ ] **Step 6: Update CLAUDE.md testing section**

Replace the testing section in CLAUDE.md with:

```markdown
## Testing

### Shell script tests
```bash
bash tests/test-gate-mechanical.sh
bash tests/test-audit-write.sh
bash tests/test-session-health.sh
```

### JSON validation
```bash
jq empty .claude-plugin/plugin.json
jq empty hooks/hooks.json
```

### Manual testing
```bash
/autotune              # Full scan
/autotune permissions  # Single area
/autotune --dry-run    # Report only
```
```

- [ ] **Step 7: Final commit**

```bash
git add CLAUDE.md
git commit -m "feat: update testing docs with actual test commands"
```

- [ ] **Step 8: Create PR**

Create a PR from the implementation branch to main with a summary of all changes.
