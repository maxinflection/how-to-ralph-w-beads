# Acceptance Criteria Pattern Examples

This directory contains examples of different acceptance criteria patterns for common scenarios.

## Patterns

1. **[test-backed.md](test-backed.md)** - Using test frameworks (preferred)
2. **[command-output.md](command-output.md)** - Verifying command output
3. **[existence-checks.md](existence-checks.md)** - File and export verification
4. **[llm-as-judge.md](llm-as-judge.md)** - Subjective criteria evaluation

## Quick Reference

| Pattern | When to Use | Example |
|---------|-------------|---------|
| Test-backed | Functionality, behavior | `npm test auth.test.ts` |
| Command output | API responses, CLI tools | `curl -s /health` |
| Existence | Files, exports, routes | `test -f src/component.ts` |
| LLM-as-judge | UX, tone, design | `MANUAL` with rubric |

See [docs/ACCEPTANCE_CRITERIA.md](../../docs/ACCEPTANCE_CRITERIA.md) for the full standards document.
