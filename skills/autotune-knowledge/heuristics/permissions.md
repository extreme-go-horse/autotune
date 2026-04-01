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
