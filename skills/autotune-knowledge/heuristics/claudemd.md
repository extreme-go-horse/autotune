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
