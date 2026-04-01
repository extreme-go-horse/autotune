# BEST_PRACTICES.md — Content Specification

**Date**: 2026-04-01
**Status**: Design approved, pending implementation
**Parent spec**: 2026-04-01-autotune-plugin-design.md
**Deliverable**: `autotune/skills/autotune-knowledge/references/BEST_PRACTICES.md`

---

## 1. Purpose

A curated, source-code-derived reference file that ships with the autotune plugin. Gets `@`-included in the user's CLAUDE.md to inject battle-tested knowledge about Claude Code internals directly into every session's context.

**Not a tutorial** — a dense, actionable cheat sheet for power users. Every line earns its token cost.

---

## 2. Source of Truth Mapping

Each practice traces back to specific source code in `~/.claude/cc-original-src/`:

| Practice area | Source files | Key insight |
|---------------|-------------|-------------|
| Token economy | `QueryEngine.ts`, `context.ts` | CLAUDE.md content injected into prompt assembly every turn |
| Sub-agent cost | `Task.ts`, `coordinator/` | Sub-agents get independent context windows, don't consume parent |
| Prompt caching | `query.ts`, `costHook.ts` | Cache read tokens tracked separately; disabling = 5x cost multiplier |
| Permissions | `setup.ts`, `tools.ts`, `Tool.ts` | Permission checks at execution time, not startup; allow list = zero overhead |
| Hooks lifecycle | `hooks/`, `setup.ts` | `captureHooksConfigSnapshot()` freezes hooks at startup |
| Memory recall | `memdir/findRelevantMemories.ts` | Side-query model step selects memories, not keyword match |
| Memory extraction | `memdir/extractMemories.ts` | Forked-agent style with restricted tool permissions |
| Skills discovery | `skills/`, `commands.ts` | Skills auto-discovered by model matching description; commands need explicit /invoke |
| MCP tools | `tools/mcp`, `server/` | Dynamic discovery; output handling supports persistence; timeout defaults |
| Plugin loading | `utils/plugins/pluginLoader.ts` | Manifest validation, hook loading, duplicate detection at load time |
| Cost tracking | `costHook.ts`, `cost-tracker.ts` | Token counts, cache ratios, API latency, tool duration all tracked |
| Session setup | `setup.ts` | 11-step bootstrap sequence; hook snapshot early; session memory not lazy |
| Compaction | `query.ts`, `context.ts` | Compaction triggered by context size; session memory updates help quality |

---

## 3. Content Specification

### Section: Token Economy

```markdown
## Token Economy
- Sub-agents don't consume parent context — delegate freely, they get their own window
- CLAUDE.md is loaded every turn — every line costs tokens across the entire session
- Use @-includes to keep CLAUDE.md modular; included files are injected every turn, so they still cost tokens — but splitting keeps each file focused and editable
- Prompt caching saves ~80% on repeated context — never disable without a specific reason
- `ctx_execute_file` keeps analysis output in sandbox; `Read` pulls it into your context window
- Compaction quality improves when session memory is fresh — the system uses it as a guide
```

**Token cost**: ~180 tokens. **Value**: prevents the #1 waste pattern (bloated CLAUDE.md).

### Section: Permissions

```markdown
## Permissions
- Add frequently-approved tools to allow list — each manual approval wastes ~5 seconds + context
- Permission checks happen at execution time, not startup — allow list has zero overhead
- Deny sensitive paths explicitly: .env, secrets/, credentials, *.key files
- Use prefix matching for Bash rules: `Bash(git:*)` covers git status, git diff, git log etc.
- `defaultMode` in settings.json sets the starting permission mode — power users benefit from `acceptEdits`
```

**Token cost**: ~140 tokens. **Value**: eliminates repetitive permission friction.

### Section: Memory

```markdown
## Memory
- MEMORY.md is an index (pointers to files), not storage — keep entries under 150 chars each
- Memory recall is model-mediated (LLM selects relevant memories), not keyword search
- Good descriptions matter more than clever names — the model reads descriptions to decide relevance
- Stale memories waste recall budget and can mislead — prune quarterly
- Memory extraction runs in a forked agent with restricted tools — it can't modify your code
```

**Token cost**: ~140 tokens. **Value**: prevents memory system degradation.

### Section: Hooks

```markdown
## Hooks
- Hooks are snapshotted at startup via captureHooksConfigSnapshot() — mid-session changes don't apply
- Restart Claude Code after modifying hooks for changes to take effect
- PreToolUse hooks can block actions with exit code 2 — use for guardrails
- Keep hook scripts fast (<100ms) — they run on the critical path of every tool execution
- PostToolUse hooks are good for logging and auditing — they don't block the action
- Common events (see cc-original-src for full list): PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd, PreCompact, PostCompact, Stop, SubagentStop, FileChanged, ConfigChange, TaskCreated, TaskCompleted
```

**Token cost**: ~170 tokens. **Value**: prevents silent hook failures and performance issues.

### Section: Skills vs Commands

```markdown
## Skills vs Commands
- Skills auto-discover by matching task context — use for capabilities the model should find
- Commands require explicit /invoke — use for workflows you trigger manually
- If you repeat the same prompt >3x, it should be a command
- Skill descriptions are critical: include WHAT it does + WHEN to use it with trigger keywords
- Skills can restrict tools via allowed-tools frontmatter — use for read-only or scoped capabilities
- Commands support $ARGUMENTS and positional params ($1, $2) — commands with !`backticks` run bash before the prompt
```

**Token cost**: ~160 tokens. **Value**: prevents skill/command misuse and discovery failures.

### Section: MCP Servers

```markdown
## MCP Servers
- Set MCP_TIMEOUT for slow-starting servers — default may be too aggressive for heavy servers
- MAX_MCP_OUTPUT_TOKENS defaults to 25000 — raise for data-heavy servers, lower for chatty ones
- Dead MCP servers slow down tool discovery on every session start — prune regularly
- Plugin MCP servers start automatically when the plugin is enabled
- MCP tool permissions use exact match or server-prefix: `mcp__github` (all tools) or `mcp__github__get_issue` (specific) — no wildcards
```

**Token cost**: ~140 tokens. **Value**: prevents MCP-related latency and cost waste.

### Section: Settings Hierarchy

```markdown
## Settings
- Precedence (high→low): managed policy > CLI args > local project > shared project > user global
- Settings merge hierarchically — deny rules accumulate across all levels
- Use .claude/settings.local.json for personal project overrides (auto-gitignored)
- Environment variables in settings.json `env` key apply to every session automatically
```

**Token cost**: ~100 tokens. **Value**: prevents settings confusion and accidental overrides.

---

## 4. Total Budget

| Section | Estimated tokens |
|---------|-----------------|
| Token Economy | ~180 |
| Permissions | ~140 |
| Memory | ~140 |
| Hooks | ~170 |
| Skills vs Commands | ~160 |
| MCP Servers | ~140 |
| Settings | ~100 |
| **Total** | **~1030** |

**Budget target**: <1200 tokens. This file is loaded every turn via @-include, so every token must earn its place.

---

## 5. Maintenance Rules

1. **Density over length** — if a practice can be said in fewer words, rewrite it
2. **Source-verified only** — every practice must trace to source code or confirmed behavior
3. **No opinions** — only verifiable facts about Claude Code internals
4. **Versioned** — BEST_PRACTICES.md includes a version comment at top for update tracking
5. **User owns it** — plugin suggests updates, never force-writes; user can add/remove practices
6. **Token-conscious** — any update must include token delta; total must stay under budget

---

## 6. Injection Mechanism

The `claudemd-tuner` agent handles injection:

1. Checks if `@~/.claude/BEST_PRACTICES.md` (exact canonical path) already exists in user's CLAUDE.md
2. If not, copies `BEST_PRACTICES.md` from plugin root to a stable location: `~/.claude/BEST_PRACTICES.md` (avoids dependency on plugin cache path which uses `cache/<marketplace>/<plugin>/<version>/` — `@-include` does not support glob expansion)
3. Proposes adding `@~/.claude/BEST_PRACTICES.md` to user's CLAUDE.md
4. Shows diff of what will be added to context
5. Applies with consent
6. Sets `best_practices_injected: true` in `~/.claude/autotune/config.json`
7. On plugin updates: compares installed BEST_PRACTICES.md version with `~/.claude/BEST_PRACTICES.md`, proposes update if newer

Idempotent: re-running when already injected → skip.
