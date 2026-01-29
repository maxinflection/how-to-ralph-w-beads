# Acceptance Criteria Standards for Ralph+Beads

## The Problem

Ralph loops can run forever if exit conditions are vague. Acceptance criteria MUST be **verifiable** - either programmatically or by explicit LLM-as-judge review. Without clear verification, the build agent cannot know when work is truly complete.

## Required Properties

Every acceptance criterion must be:

### 1. Specific
Names exact behavior, not vague quality.

| Bad | Good |
|-----|------|
| "Code is clean" | "No lint errors from `npm run lint`" |
| "Works correctly" | "Returns 200 status code with user data" |
| "Handles errors" | "Returns 400 for invalid email format" |

### 2. Measurable
Has a binary pass/fail check.

| Bad | Good |
|-----|------|
| "Performance is good" | "Response time < 200ms for 95th percentile" |
| "Fast enough" | "`time npm run build` completes in < 30s" |
| "Minimal bundle size" | "Bundle size < 500KB per `npm run analyze`" |

### 3. Automatable
Can be verified by running a command with a clear exit code.

| Bad | Good |
|-----|------|
| "UI looks correct" | "Playwright visual regression test passes" |
| "API works" | "`curl -s localhost:3000/health` returns `{"status":"ok"}`" |
| "Tests pass" | "`npm test -- --grep "auth"` exits with code 0" |

---

## Standard Format

Each acceptance criterion should follow this pattern:

```
- [ ] {description} | `{verification_command}` | {expected_outcome}
```

Where:
- **description**: Human-readable explanation of what must be true
- **verification_command**: Exact command to run (or `MANUAL` for non-automatable)
- **expected_outcome**: Exit code (0 for success) or expected output

### Examples

```markdown
- [ ] Unit tests pass | `npm test src/auth.test.ts` | exit 0
- [ ] No lint errors | `npm run lint -- src/auth/` | exit 0
- [ ] Endpoint returns health | `curl -s localhost:3000/health` | {"status":"ok"}
- [ ] File exists | `test -f src/auth/index.ts` | exit 0
- [ ] Export present | `grep -q "export.*AuthService" src/index.ts` | exit 0
```

---

## Acceptance Criteria Patterns

### Pattern 1: Test-Backed (Preferred)

Use existing test infrastructure. Most reliable and maintainable.

```markdown
- [ ] Unit tests pass | `npm test src/auth.test.ts` | exit 0
- [ ] E2E login flow works | `npm run e2e -- --grep "login"` | exit 0
- [ ] TypeScript compiles | `npm run typecheck` | exit 0
- [ ] All tests green | `pytest tests/unit/` | exit 0
- [ ] Go tests pass | `go test ./pkg/auth/...` | exit 0
```

**When to use**: Any functionality that can be tested. Should be the default.

**Framework-agnostic commands**:
- JavaScript/TypeScript: `npm test`, `yarn test`, `pnpm test`
- Python: `pytest`, `python -m pytest`, `python -m unittest`
- Go: `go test ./...`
- Rust: `cargo test`
- Generic: Check project's `AGENTS.md` for specific commands

### Pattern 2: Command Output

Verify behavior by checking command output directly.

```markdown
- [ ] Health endpoint works | `curl -s localhost:3000/health` | {"status":"ok"}
- [ ] CLI shows version | `./myapp --version` | contains "1.0.0"
- [ ] Config is valid | `./myapp config validate` | exit 0
- [ ] No TODOs remain | `grep -r "TODO" src/feature/` | exit 1 (empty = success)
- [ ] Port is listening | `nc -z localhost 3000` | exit 0
```

**When to use**: Quick verification of endpoints, CLI tools, or file content.

### Pattern 3: Existence Checks

Verify files, exports, or patterns exist.

```markdown
- [ ] Component file exists | `test -f src/components/Button.tsx` | exit 0
- [ ] Export in index | `grep -q "export.*Button" src/components/index.ts` | exit 0
- [ ] Route registered | `grep -q '"/api/users"' src/routes.ts` | exit 0
- [ ] Migration created | `ls db/migrations/*create_users* 2>/dev/null` | exit 0
- [ ] Hook installed | `test -x .git/hooks/pre-commit` | exit 0
```

**When to use**: Ensuring structural requirements are met.

### Pattern 4: Metrics and Thresholds

Verify quantitative requirements.

```markdown
- [ ] Bundle under limit | `npm run build && stat -f%z dist/main.js | awk '$1 < 500000'` | exit 0
- [ ] Coverage above 80% | `npm test -- --coverage | grep "All files" | awk '{print $4}' | awk '$1 >= 80'` | exit 0
- [ ] Response time OK | `curl -w '%{time_total}' -s localhost:3000/api | awk '$1 < 0.2'` | exit 0
- [ ] Line count under 500 | `wc -l < src/utils.ts | awk '$1 < 500'` | exit 0
```

**When to use**: Performance, size, or coverage requirements.

### Pattern 5: LLM-as-Judge (For Subjective Criteria)

Some criteria resist programmatic validation. Use explicit LLM review.

```markdown
- [ ] Error messages user-friendly | `MANUAL` | LLM review confirms messages explain problem and suggest action
- [ ] Documentation clear | `MANUAL` | LLM review confirms docs are understandable without prior context
- [ ] Code follows patterns | `MANUAL` | LLM review confirms consistency with existing codebase style
```

**Format for LLM-as-judge criteria**:
```markdown
- [ ] {what to evaluate} | `MANUAL` | LLM review confirms: {specific criteria}
     Artifact: {file or output to review}
     Rubric:
       1. {criterion 1}
       2. {criterion 2}
```

**Example**:
```markdown
- [ ] Welcome message tone appropriate | `MANUAL` | LLM review confirms warmth and professionalism
     Artifact: src/messages/welcome.ts
     Rubric:
       1. Uses conversational but professional language
       2. Clearly explains next steps
       3. Avoids jargon and technical terms
```

**When to use**: Creative quality, UX feel, documentation clarity, design aesthetics.

---

## Anti-Patterns (NEVER Use)

| Anti-Pattern | Why It Fails | Better Alternative |
|--------------|--------------|-------------------|
| "Works correctly" | Unfalsifiable | Specific test case with expected output |
| "Handles edge cases" | Unbounded scope | List exact edge cases to handle |
| "Good performance" | No threshold | Specific metric: "< 200ms p95" |
| "Clean code" | Subjective | "No lint errors" or specific lint rules |
| "User-friendly" | Vague | LLM-as-judge with explicit rubric |
| "Properly implemented" | Circular | Test cases that verify behavior |
| "Following best practices" | Undefined | Link to specific guidelines or use lint rules |
| "Robust error handling" | Unclear scope | List specific error cases: "Returns 400 for missing email" |

---

## Verification in Build Mode

The BUILDING prompt requires this validation flow:

```bash
# 1. Read acceptance criteria from issue
bd show <id> --json | jq -r '.[0].acceptance_criteria'

# 2. For each criterion with a command, run it
npm test src/auth.test.ts
echo "Exit code: $?"  # Must be 0

npm run lint -- src/auth/
echo "Exit code: $?"  # Must be 0

# 3. For MANUAL criteria, document the review
# "Reviewed welcome.ts - messages are clear and actionable"

# 4. Only close when ALL criteria verified
bd close <id> --reason "
Verified:
- [x] Unit tests pass (npm test auth.test.ts - exit 0)
- [x] Lint clean (npm run lint - exit 0)
- [x] Welcome message tone (LLM review - meets rubric)
"
```

### Handling Failures

If any criterion fails:

1. **Trivial fix** (typo, syntax, <10 lines): Fix inline and re-verify
2. **Substantial work needed**: Create blocking issue:
   ```bash
   bd create "Fix: Auth tests failing on edge case" --type bug --priority 1 \
     --description "Discovered while validating htrwb-xyz" \
     --acceptance "- [ ] Auth edge case test passes | \`npm test -- --grep 'edge'\` | exit 0"
   bd dep add <current-id> <new-bug-id>
   bd update <current-id> --status blocked --notes "Blocked by <new-bug-id>"
   ```

---

## Writing Good Acceptance Criteria

### During Planning

When creating issues, derive AC from requirements:

1. **What behavior is expected?** → Unit test criterion
2. **What can go wrong?** → Error handling criteria
3. **What are the boundaries?** → Edge case criteria
4. **How do we know it's integrated?** → Integration test criterion
5. **What commands verify success?** → Include exact commands

### Template

```bash
bd create "Implement user login" --type task --priority 2 \
  --description="
## Context
Users need to authenticate to access protected routes.

## References
- src/api/routes/auth.ts
- docs/auth-spec.md
" \
  --acceptance="
- [ ] Login returns JWT for valid credentials | \`npm test -- --grep 'login valid'\` | exit 0
- [ ] Login returns 401 for invalid password | \`npm test -- --grep 'login invalid'\` | exit 0
- [ ] Login returns 400 for missing email | \`npm test -- --grep 'login missing'\` | exit 0
- [ ] Rate limiting works | \`npm test -- --grep 'login rate'\` | exit 0
- [ ] All auth tests pass | \`npm test src/auth/\` | exit 0
- [ ] No lint errors | \`npm run lint -- src/auth/\` | exit 0
"
```

---

## Exit Condition Logic

The loop exits when ALL of these are true:

1. `bd ready` returns empty (no unblocked work)
2. All closed issues have verified acceptance criteria
3. No issues stuck in `in_progress` for >3 iterations

This creates a deterministic exit condition: work is done when there's nothing left to do AND everything that was done meets its criteria.
