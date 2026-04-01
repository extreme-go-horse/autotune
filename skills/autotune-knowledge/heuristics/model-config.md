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
