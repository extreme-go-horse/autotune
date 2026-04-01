## Summary

<!-- What changed? Be specific — Copilot uses this for review context. -->

## Motivation / Why

<!-- Why is this change needed? What problem does it solve? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring (no behavior change)
- [ ] Chore / infra / config
- [ ] Documentation

## Testing done

<!-- Describe how you tested. Include: did diagnostics run correctly? No false positives/negatives? -->
[NO_TEST_SUITE: autotune — manually tested diagnostics]

## Related issues

<!-- Closes #N -->

## Copilot review focus areas

> This repo is a Claude Code setup optimizer plugin — it audits permissions, validates
> CLAUDE.md, checks plugin health, and diagnoses MCP server issues.
> Please pay extra attention to:

- **Permissions audit correctness**: Can a misconfigured permission pass undetected (false negative)? Are there false positives that would cause noise?
- **CLAUDE.md parsing**: Is the parser handling edge cases — empty files, missing sections, non-UTF8 encoding, nested includes?
- **Plugin manifest validation**: Are all required fields checked? Does the validator handle missing or malformed `plugin.json`?
- **MCP server discovery**: Are timeout values reasonable? Is auth validation complete? Are unreachable servers handled gracefully?
- **Bash 3.2 compatibility**: No `declare -A` associative arrays, no `mapfile`/`readarray`, no `&>>` append-redirect?
- **Shell safety**: `set -euo pipefail`? No unquoted variables? Proper quoting of paths? No `eval` on user input?

## Checklist

- [ ] Closes an issue
- [ ] Tests pass (or NO_TEST_SUITE documented)
- [ ] No secrets in code or commits
- [ ] `set -euo pipefail` at top of every new shell script
- [ ] Bash 3.2 compatible (no bash 4+ features)
- [ ] No `eval` on user-supplied input
