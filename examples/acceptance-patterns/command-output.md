# Pattern 2: Command Output Verification

Verify behavior by checking command output directly.

## When to Use

- API endpoint responses
- CLI tool output
- Health checks
- Configuration validation
- Process verification

## Format

```
- [ ] {expected behavior} | `{command}` | {expected output or exit code}
```

## Examples

### HTTP Endpoints

```markdown
- [ ] Health endpoint returns OK | `curl -s localhost:3000/health` | {"status":"ok"}
- [ ] API returns 200 | `curl -s -o /dev/null -w "%{http_code}" localhost:3000/api/users` | 200
- [ ] Auth header required | `curl -s -o /dev/null -w "%{http_code}" localhost:3000/api/protected` | 401
- [ ] CORS headers present | `curl -sI localhost:3000 | grep -i "access-control"` | exit 0
```

### CLI Tools

```markdown
- [ ] Version command works | `./myapp --version` | contains "1.0.0"
- [ ] Help is displayed | `./myapp --help | grep -q "Usage"` | exit 0
- [ ] Config validation passes | `./myapp config validate` | exit 0
- [ ] Dry run succeeds | `./myapp deploy --dry-run` | exit 0
```

### Process/Service Verification

```markdown
- [ ] Port is listening | `nc -z localhost 3000` | exit 0
- [ ] Service is running | `pgrep -f "myservice"` | exit 0
- [ ] Database accepts connections | `pg_isready -h localhost` | exit 0
```

### File Content Checks

```markdown
- [ ] No TODOs in production code | `grep -r "TODO" src/ | grep -v test` | exit 1
- [ ] No console.log in prod | `grep -r "console.log" src/ --include="*.ts" | grep -v ".test."` | exit 1
- [ ] License header present | `head -1 src/index.ts | grep -q "Copyright"` | exit 0
```

## Tips

1. **Use `-s` for silent curl** - Cleaner output
2. **Capture exit codes** - `command || echo "failed"`
3. **Use grep for partial matching** - When exact output varies
4. **Consider timeout** - `timeout 5 curl ...` for network calls

## Handling Variable Output

When output contains timestamps or IDs:

```markdown
# Bad - will fail due to timestamp
- [ ] Response correct | `curl -s /api/time` | {"time":"2024-01-01T00:00:00Z"}

# Good - check structure only
- [ ] Response has time field | `curl -s /api/time | jq -e '.time'` | exit 0
```
