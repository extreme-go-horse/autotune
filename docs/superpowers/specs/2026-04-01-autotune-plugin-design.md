# Autotune — Claude Code Setup Optimizer Plugin

**Date**: 2026-04-01
**Status**: Design approved, pending implementation plan
**Author**: Pedro + Claude (brainstorm)

---

## 1. Overview

Autotune is a Claude Code plugin that diagnoses, optimizes, and continuously enforces best practices on a user's Claude Code setup. It combines deep diagnostic agents with real-time enforcement hooks to maximize Claude's usefulness over time.

**Target audience**: Power users with existing setups.
**V1 focus**: Wizard/diagnostic-first (scan + fix), with lightweight enforcement hooks. Full monitoring in v2.

### Core metaphor

Like audio autotune: takes the user's setup "voice" and corrects the pitch automatically — both tuning from scratch and keeping it tuned over time.

---

## 2. Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Audience | Power users, both wizard + monitor, wizard first | Highest impact for users who already have complex setups |
| Name | `autotune` | Strong metaphor — works for wizard ("tune from zero") and monitor ("stay tuned") |
| Auto-apply | Yes, with consent | Power users want efficiency, not just reports |
| V1 scope | Permissions, CLAUDE.md hygiene, model config/caching, plugin health, MCP health | Prioritized by impact analysis from XGH reports |
| Knowledge base | `cc-original-src/` (SoT) + XGH reports (derived, trusted) | Source code is ground truth; reports are pre-digested analysis |
| Persistence | Filesystem simple: `~/.claude/autotune/` with JSONs | KISS — portable, inspectable, git-friendly |
| Architecture | Specialist agents + enforcement hooks | Agents do deep analysis, hooks maintain what agents tuned |
| Enforcement | 3 layers: mechanical (shell), semantic (skill/LLM), deep (agent) | Graduated cost: 0 tokens → few tokens haiku → full agent |
| Idempotency | All checks and fixes must be idempotent | Safe to run N times without side effects |
| Hot files | First-class concept — files loaded every turn have outsized token cost | CLAUDE.md, settings.json, MEMORY.md, .mcp.json, hooks.json |
| Best practices | Plugin maintains BEST_PRACTICES.md, @-included in user's CLAUDE.md | Not just defensive (remove bad) but offensive (inject good) |
| Plugin template | `~/.claude/claude-code-plugin-template/` + `install-local-plugin` skill | Scaffolding base for implementation |

---

## 3. Architecture

### Plugin Structure

```
autotune/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── permissions-tuner.md
│   ├── claudemd-tuner.md
│   ├── model-tuner.md
│   ├── plugin-tuner.md
│   └── mcp-tuner.md
├── hooks/
│   └── hooks.json
├── scripts/
│   ├── gate-mechanical.sh
│   ├── audit-write.sh
│   └── session-health.sh
├── commands/
│   └── autotune.md
├── skills/
│   └── autotune-knowledge/
│       ├── SKILL.md
│       ├── heuristics/
│       │   ├── permissions.md
│       │   ├── claudemd.md
│       │   ├── model-config.md
│       │   ├── plugins.md
│       │   └── mcp.md
│       └── references/
│           └── BEST_PRACTICES.md
└── state/
    └── README.md
```

### Data Flow

1. `/autotune` spawns relevant agents (max 4 parallel to leave at least one subagent slot free for other tools and system use); each reads source + config, produces findings, applies fixes with consent, persists state to `~/.claude/autotune/<area>.json`
2. **Compilation step**: after all agents complete (or fail), orchestrator merges `findings/*.json` into `rules.json` atomically (write to temp file, rename). If an agent failed, its area is excluded from compilation and marked as `"error"` in `last-run.json`.
3. Hooks read `~/.claude/autotune/rules.json` (compiled output) for enforcement
4. Agents feed hooks; hooks protect what agents tuned

**Key principle**: Agents are write-heavy (diagnose and fix). Hooks are read-only (validate against established rules).

### Three Enforcement Layers

| Layer | Type | Runtime | Token cost | When |
|-------|------|---------|------------|------|
| Mechanical | Shell script | O(1), deterministic | 0 | PreToolUse Write/Edit |
| Semantic | Skill invoked by model (best-effort) | O(n), heuristic | Skill payload (haiku) | PreToolUse on hot files |
| Deep | Full agent on-demand | O(n²), cross-analysis | More (sonnet/opus) | `/autotune` command |

**Boundary rule**: If the check is O(1) and deterministic (read a JSON, verify a file exists) → hook. If it requires analysis, heuristics, or decisions → agent.

**Important**: Semantic enforcement is best-effort (model-mediated, not guaranteed). The model may skip skill invocation under context pressure. Critical guardrails MUST remain in the mechanical layer. The semantic layer is advisory — it catches what it can, but the system must be safe without it.

---

## 4. Agents

Each agent follows a standard contract:

1. **Scan** → produces `findings[]`
2. **Report** → presents findings with severity (critical/warning/info)
3. **Fix** → applies with consent, idempotent
4. **Persist** → saves to `~/.claude/autotune/<area>.json`

### 4.1 permissions-tuner

**Diagnostics:**
- Reads `settings.json` (all levels) + analyzes usage patterns in session transcripts (`~/.claude/projects/*/sessions/*/` JSONL files)
- **Privacy gate**: before transcript access, prompts user: "Autotune wants to analyze session history to optimize permissions. Only tool_use/tool_result events are parsed (not full conversation content). Allow?" Transcript path structure is an implementation contract — version-check on startup.
- Detects: tools approved repeatedly but without allow rule, conflicting deny/allow, sensitive paths without protection, suboptimal permission mode

**Fixes:**
- Promotes frequently-approved tools to allow rules
- Removes redundant/conflicting denies
- Adds denies for sensitive paths (.env, secrets/, credentials)
- Suggests defaultMode based on usage profile

### 4.2 claudemd-tuner

**Diagnostics:**
- Measures token weight of each hot file (estimated as `char_count / 3` — conservative multiplier for markdown-heavy content; `char/4` underestimates by ~30% for code/markup)
- Detects: bloat (dead lines, redundancy), conflicting instructions, content that should be skill/command, missing `@BEST_PRACTICES.md`
- Cross-references: CLAUDE.md global vs project vs MEMORY.md — finds overlaps

**Fixes:**
- Migrates repetitive instructions to skills
- Removes dead/redundant lines
- Injects `@BEST_PRACTICES.md`
- Suggests compaction when token budget exceeds threshold

### 4.3 model-tuner

**Diagnostics:**
- Verifies: prompt caching enabled, thinking tokens configured, model selection (opus vs sonnet vs haiku by context)
- Analyzes env vars: `MAX_THINKING_TOKENS`, `DISABLE_PROMPT_CACHING`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `CLAUDE_CODE_SUBAGENT_MODEL`
- Cross-check: heavy MCP servers + caching disabled = red flag

**Fixes:**
- Enables prompt caching if disabled
- Configures subagent model (haiku for lightweight tasks)
- Suggests thinking tokens budget based on user's work type

### 4.4 plugin-tuner

**Diagnostics:**
- Detects: ghost plugins (enabled but not installed), duplicates, namespace conflicts, outdated plugins
- Validates manifests of all installed plugins
- Checks for plugin hook conflicts

**Fixes:**
- Removes ghost plugin references
- Resolves namespace conflicts
- Disables plugins with conflicting hooks (with consent)

### 4.5 mcp-tuner

**Diagnostics:**
- Health check: attempts startup of each MCP server, measures response time
- Detects: dead servers, slow servers (> timeout), servers without useful tools, duplicate servers
- Validates configuration (`MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `MAX_MCP_OUTPUT_TOKENS`)

**Fixes:**
- Removes/disables dead servers
- Adjusts timeouts for slow servers
- Suggests `MAX_MCP_OUTPUT_TOKENS` based on actual usage

---

## 5. Hooks & Enforcement

### hooks.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gate-mechanical.sh"
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
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/audit-write.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-health.sh"
          }
        ]
      }
    ]
  }
}
```

### Gate Mechanical (`gate-mechanical.sh`)

Runs on PreToolUse Write/Edit. Zero tokens. Deterministic checks:

- **Hot file bloat**: CLAUDE.md > threshold lines → block
- **Sensitive path**: Write to `.env`, `credentials.*`, `secrets/` without deny rule → block
- **Settings conflict**: deny rule contradicting existing allow rule → block
- **Caching sabotage**: `DISABLE_PROMPT_CACHING=1` being added → block

Script receives `tool_input` via stdin (JSON with `file_path` and `content`), validates, returns exit code 0 (pass) or 2 (block with message).

### Semantic Enforcement (via Skill)

The `autotune-knowledge` skill is auto-invoked by the model when it detects writes to hot files. It instructs the model to:

- Compare proposed write against `BEST_PRACTICES.md`
- Check if new CLAUDE.md instruction contradicts existing ones
- Validate if permission change makes sense in context of full setup

Cost: few tokens on haiku. Only triggers on hot files. The skill's description ensures auto-discovery: Claude sees a write to a hot file, matches the skill description ("Use when writing or editing CLAUDE.md, settings.json..."), and loads the heuristics before proceeding.

### Audit Trail (`audit-write.sh`)

Runs on PostToolUse Write/Edit. Logs changes to hot files:

```json
{"ts":"2026-04-01T15:30:00Z","file":"~/.claude/CLAUDE.md","action":"edit","lines_delta":12,"token_weight_delta":340}
```

**Rotation**: max 10,000 entries (~1MB). When exceeded, truncate oldest 50%. Configurable via `config.json` threshold `audit_max_entries`.

### Session Health (`session-health.sh`)

Runs on SessionStart. Quick scan:

- Total token weight of hot files
- Last autotune run (warn if > 7 days)
- rules.json integrity (exists, parseable)
- MCP servers responding (parallel ping, max 2s per server, total cap 5s — skip unresponsive)

Output: status line — "autotune: healthy" or "autotune: 2 warnings — run `/autotune` for details"

---

## 6. Command `/autotune`

```markdown
---
description: Diagnose and tune your Claude Code setup for maximum effectiveness
argument-hint: [area|all] [--dry-run] [--report-only]
allowed-tools: Bash(cat:*), Bash(wc:*), Bash(jq:*), Read, Glob, Grep, Write, Edit, Agent
---
```

### Usage

```
/autotune              # All 5 agents, report + fix
/autotune permissions  # Only permissions-tuner
/autotune claudemd     # Only claudemd-tuner
/autotune model        # Only model-tuner
/autotune plugins      # Only plugin-tuner
/autotune mcp          # Only mcp-tuner
/autotune --dry-run    # Report without applying fixes
/autotune --report-only # Generate report to ~/.claude/autotune/report.md
```

### Orchestration Flow

1. Parse arguments (area or all, flags)
2. Read previous state (`~/.claude/autotune/*.json`) for drift comparison
3. Spawn relevant agent(s) — max 4 parallel if `all`, 5th runs after first completes
4. Each agent returns `findings[]` in standard format. If an agent fails/times out: mark area as `"error"` in `last-run.json`, surface failure in report, exclude from compilation
5. Consolidate findings, sort by severity
6. Present report to user
7. If not `--dry-run`/`--report-only`: apply fixes with consent per finding
8. Recompile `rules.json` atomically (write-tmp + rename) from **post-fix state** — ensures hooks enforce the corrected config, not stale pre-fix findings
9. Persist new state + updated scores

### Finding Format

```json
{
  "id": "perm-001",
  "area": "permissions",
  "severity": "critical|warning|info",
  "title": "Bash(git status) approved 12x but not in allow list",
  "description": "You approve this every session. Adding to allow saves ~24 permission prompts/week.",
  "fix": {
    "type": "settings-merge",
    "target": "~/.claude/settings.json",
    "patch": {"permissions.allow": ["Bash(git status:*)"]}
  },
  "idempotent": true
}
```

### Consolidated Output

```
autotune scan complete

  CRITICAL (2)
    [perm-001] Bash(git status) approved 12x but not in allow list
    [model-001] Prompt caching disabled — estimated +$2.40/day

  WARNING (3)
    [cmd-001] CLAUDE.md at 187 lines (threshold: 150) — 4200 tokens/turn
    [mcp-001] MCP server "context-mode" not responding
    [plug-001] Plugin "experimental" enabled but not installed

  INFO (1)
    [cmd-002] @BEST_PRACTICES.md not included in CLAUDE.md

  Apply fixes? [all / cherry-pick / skip]
```

---

## 7. Knowledge Base & BEST_PRACTICES.md

### Skill `autotune-knowledge`

```yaml
---
name: autotune-knowledge
description: Claude Code setup optimization knowledge base. Use when writing or editing
  CLAUDE.md, settings.json, hooks, permissions, or any configuration file. Also use when
  user asks about Claude Code best practices, performance, or cost optimization.
---
```

Loads heuristics derived from source code (`cc-original-src/`) and XGH reports. Serves as the "brain" feeding both agents and semantic hooks.

### Heuristics Structure

```
skills/autotune-knowledge/
├── SKILL.md
├── heuristics/
│   ├── permissions.md          # Derived from setup.ts, tools.ts
│   ├── claudemd.md             # Derived from QueryEngine.ts, context.ts
│   ├── model-config.md         # Derived from costHook.ts, query.ts
│   ├── plugins.md              # Derived from pluginLoader.ts
│   └── mcp.md                  # Derived from server/, tools/mcp
└── references/
    └── BEST_PRACTICES.md
```

### BEST_PRACTICES.md

User-facing file, @-included in their CLAUDE.md. Contains curated wisdom:

- **Token Economy**: sub-agents don't consume parent context; CLAUDE.md costs tokens every turn; prompt caching saves ~80%; use @-includes for lean CLAUDE.md
- **Permissions**: add frequently-approved tools to allow list; deny sensitive paths; permission checks are at execution time
- **Memory**: MEMORY.md is an index not storage; recall is model-mediated; prune stale memories
- **Hooks**: snapshotted at startup; PreToolUse can block (exit 2); keep scripts fast (<100ms)
- **Skills vs Commands**: skills auto-discover, commands require /invoke; if you repeat a prompt >3x make it a command
- **MCP Servers**: set timeouts; raise MAX_MCP_OUTPUT_TOKENS for data-heavy servers; prune dead servers

### Lifecycle

1. Plugin installs `BEST_PRACTICES.md` on first run
2. Agent `claudemd-tuner` injects `@BEST_PRACTICES.md` in user's CLAUDE.md (with consent)
3. Future plugin versions may update content
4. User can override/extend — file belongs to user, plugin suggests but never force-writes

---

## 8. State & Persistence

### `~/.claude/autotune/`

```
~/.claude/autotune/
├── config.json          # Autotune preferences (thresholds, enabled checks)
├── last-run.json        # Timestamp + summary of last /autotune
├── findings/
│   ├── permissions.json
│   ├── claudemd.json
│   ├── model.json
│   ├── plugins.json
│   └── mcp.json
├── rules.json           # Consolidated rules for hooks (compiled output)
├── audit.jsonl          # Append-only log of writes to hot files
└── scores.json          # Health score per area (0-100) + trend
```

### config.json

```json
{
  "version": 1,
  "thresholds": {
    "claudemd_max_lines": 150,
    "claudemd_max_tokens": 5000,
    "hot_files_total_tokens": 15000,
    "stale_run_days": 7,
    "mcp_timeout_ms": 5000
  },
  "enabled_checks": ["permissions", "claudemd", "model", "plugins", "mcp"],
  "auto_apply_severity": "none"
  "best_practices_injected": false
}
```

### rules.json (compiled, consumed by hooks)

```json
{
  "schema_version": 1,
  "compiled_at": "2026-04-01T15:30:00Z",
  "hot_files": [
    "~/.claude/CLAUDE.md",
    ".claude/CLAUDE.md",
    "~/.claude/settings.json",
    "~/.claude/MEMORY.md"
  ],
  "block_rules": [
    {"pattern": "\\.env(\\..+)?$", "reason": "Sensitive file (.env, .env.local, .env.production, etc.)"},
    {"pattern": "credentials", "reason": "Credentials file without deny rule"},
    {"pattern": "secrets/", "reason": "Secrets directory without deny rule"},
    {"pattern": "DISABLE_PROMPT_CACHING", "reason": "Caching sabotage"}
  ],
  "warn_rules": [
    {"file": "~/.claude/CLAUDE.md", "max_lines": 150}
  ]
}
```

**Schema versioning**: `gate-mechanical.sh` checks `schema_version` on every invocation. If unrecognized version → exit 2 with "autotune rules.json schema mismatch — run `/autotune` to recompile".

### scores.json

```json
{
  "overall": 72,
  "areas": {
    "permissions": {"score": 85, "trend": "+5", "last_check": "2026-04-01"},
    "claudemd": {"score": 60, "trend": "-10", "last_check": "2026-04-01"},
    "model": {"score": 95, "trend": "0", "last_check": "2026-04-01"},
    "plugins": {"score": 50, "trend": "+20", "last_check": "2026-04-01"},
    "mcp": {"score": 70, "trend": "0", "last_check": "2026-04-01"}
  }
}
```

SessionStart hook reads `scores.json` and shows: **"autotune: 72/100 (claudemd drifting)"**

### Scoring Formula

Score per area: `100 - (critical_count * 20 + warning_count * 5 + info_count * 1)`, clamped to 0-100.
Overall: weighted average of area scores (equal weights in v1).
Trend: delta from previous run's score for that area (e.g., `"+5"` means score improved by 5 points since last `/autotune`).

### Idempotency Guarantees

- Each finding has a stable `id` (e.g., `perm-001`)
- Re-run produces same findings if nothing changed
- Fixes verify state before applying (e.g., "allow rule already exists → skip")
- `audit.jsonl` is append-only, never edited

---

## 9. V2 Roadmap (out of scope for v1)

- **Continuous monitoring**: SessionEnd hook collects session metrics, tracks trends
- **Cost efficiency analysis**: historical token/cost data, identify waste patterns
- **Memory/skills hygiene**: detect stale memories, duplicated skills, unused commands
- **Hooks optimization**: suggest useful hooks (formatters, linters) based on project type
- **Auto-apply tiers**: low-risk fixes auto-apply, medium ask, high recommend-only
- **Team mode**: shared autotune config for teams via project settings
