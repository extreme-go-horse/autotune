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

Return findings as JSON array. Each finding:

```json
{
  "id": "cmd-xxx-NNN",
  "area": "claudemd",
  "severity": "critical|warning|info",
  "title": "Short description",
  "description": "Detailed explanation with token impact",
  "fix": {
    "type": "edit|inject|suggest|report",
    "target": "~/.claude/CLAUDE.md",
    "patch": {}
  },
  "idempotent": true
}
```

Fix types:
- `edit` — modify CLAUDE.md directly (remove duplicate lines)
- `inject` — add @-include for BEST_PRACTICES.md
- `suggest` — recommend migration to skill/command (user does manually)
- `report` — show token breakdown (no automatic fix)

## Persistence

Save findings to `~/.claude/autotune/findings/claudemd.json`:

```json
{
  "area": "claudemd",
  "timestamp": "ISO-8601",
  "findings": [...],
  "score": 0-100
}
```

Score: `100 - (critical * 20 + warning * 5 + info * 1)`, clamped 0-100.
