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
