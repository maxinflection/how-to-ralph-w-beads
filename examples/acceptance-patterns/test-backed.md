# Pattern 1: Test-Backed Acceptance Criteria

Use existing test infrastructure for verification. Most reliable and maintainable.

## When to Use

- Functionality that can be unit tested
- Integration points between components
- API endpoint behavior
- Business logic validation

## Format

```
- [ ] {what is being tested} | `{test command}` | exit 0
```

## Examples

### JavaScript/TypeScript (Jest, Vitest)

```markdown
- [ ] Login returns JWT for valid credentials | `npm test -- --grep "login valid"` | exit 0
- [ ] Login returns 401 for invalid password | `npm test -- --grep "login invalid"` | exit 0
- [ ] All auth module tests pass | `npm test src/auth/` | exit 0
- [ ] TypeScript compiles without errors | `npm run typecheck` | exit 0
```

### Python (pytest)

```markdown
- [ ] User creation works | `pytest tests/test_users.py::test_create_user -v` | exit 0
- [ ] API endpoints return correct status | `pytest tests/test_api.py -v` | exit 0
- [ ] All tests pass | `pytest tests/` | exit 0
```

### Go

```markdown
- [ ] Handler tests pass | `go test ./handlers/... -v` | exit 0
- [ ] Integration tests pass | `go test ./... -tags=integration` | exit 0
- [ ] Race detection clean | `go test -race ./...` | exit 0
```

### Rust

```markdown
- [ ] Unit tests pass | `cargo test --lib` | exit 0
- [ ] Integration tests pass | `cargo test --test '*'` | exit 0
- [ ] Doc tests pass | `cargo test --doc` | exit 0
```

## Tips

1. **Be specific with grep patterns** - Target exact test names when possible
2. **Use test file paths** - More stable than test names which may change
3. **Include typecheck/lint** - Catch issues before runtime tests
4. **Consider test coverage** - Add coverage thresholds if meaningful

## Anti-Patterns to Avoid

```markdown
# Bad - too vague
- [ ] Tests pass | `npm test` | exit 0

# Good - specific test file
- [ ] Auth tests pass | `npm test src/auth/auth.test.ts` | exit 0
```
