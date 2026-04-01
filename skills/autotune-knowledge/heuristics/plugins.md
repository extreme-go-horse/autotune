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
