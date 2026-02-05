# BUILDING MODE - Implement from Beads Queue

<!-- RALPH_SCOPE: ${RALPH_SCOPE} -->

## Phase 0: Orient

**0a. Get ready work:**
- If RALPH_SCOPE is set above (non-empty): Run `bd ready --parent=${RALPH_SCOPE} --json | jq '.[0]'`
- Otherwise: Run `bd ready --json | jq '.[0]'`

This gets the highest-priority unblocked task (within scope if scoped).

**0b. Run `bd show <id>`** to read full context, acceptance criteria, and dependencies.

### Minimize Re-fetching (Efficiency)

- **Cache issue details mentally** - after `bd show`, you have the full context. Don't call `bd show` again for the same issue unless you need to verify changes.
- **Use bd ready output directly** - when closing a task, the next `bd ready` shows what's available. Don't run redundant queries.
- **Avoid repeated bd list calls** - if you just ran `bd ready`, you already know what's available.

Orientation overhead should be <15% of tool calls. If you're running `bd show` or `bd ready` repeatedly for the same information, pause and use context you already have.

**0c. Study requirements** (specs are optional):
    - If `specs/*` exists → Study specs with up to 25 parallel Sonnet subagents
    - If no specs exist → The issue description and parent epic ARE the requirements
      ```bash
      # Get parent epic for additional context
      bd show <id> --json | jq -r '.[0].parent' | xargs -I{} bd show {}
      ```
0d. Study referenced files and existing code for patterns using Sonnet subagents.
0e. Study existing test patterns: `find . -name "*.test.*" -o -name "*.spec.*" | head -10`

### Batch File Reads (Efficiency)
When you need to read multiple related files (e.g., test fixtures, module files, config files), **read them all in a single turn** using parallel Read calls. Sequential reads of related files waste turns.

```
# BAD: 5 sequential reads = 5 turns
Read fixtures/a.json → Read fixtures/b.json → Read fixtures/c.json → ...

# GOOD: 5 parallel reads = 1 turn
Read fixtures/a.json, fixtures/b.json, fixtures/c.json, ... (all at once)
```

## Tool Restrictions

**DO NOT** use TodoWrite, TaskCreate, or markdown files for task tracking.

### Edit Tool Requirement
**Before any Edit call, you MUST Read the file in this turn.** The Edit tool will reject changes to unread files. Don't waste a turn on a rejected edit—read first, then edit.

For ALL task and progress tracking, use beads:
- `bd update <id> --status in_progress` — Claim work
- `bd comments add <id> "Started X"` — Log progress (append-only, creates chronological record)
- `bd comments add <id> "Completed Y, moving to Z"` — Progress checkpoints
- `bd create --title="..." --type=task` — Create discovered work
- `bd close <id>` — Mark complete
- `bd update <id> --notes "..."` — Persistent context that should remain visible

If you find yourself reaching for TodoWrite, **STOP** and use the equivalent `bd` command.

---

## Phase 1: Claim Work

1. **Claim the task**:
   ```bash
   bd update <id> --status in_progress
   ```

## Phase 1.5: Create Test Scaffolding (BEFORE Implementation)

Before writing any implementation code, create test stubs that codify the acceptance criteria.

1. Read the acceptance criteria:
   ```bash
   bd show <id> --json | jq -r '.[0].acceptance_criteria'
   ```

2. For each testable criterion, create a test stub:
   - Parse the criterion format: `description | command | expected`
   - If the command references a test file, ensure the test exists (even as a stub)
   - Example: If AC says "Login returns JWT | `npm test auth.test.ts` | exit 0"
     Create `auth.test.ts` with: `test("login returns JWT", () => { /* TODO */ })`

3. The test stubs should:
   - Fail initially (red phase of TDD)
   - Clearly describe what needs to pass
   - Follow existing test patterns in the codebase

This ensures tests exist BEFORE implementation and forces thinking about verification.

## Phase 2: Implement

2. **Implement the functionality**:
   - Before making changes, search the codebase (don't assume not implemented)
   - Use up to 50 parallel Sonnet subagents for searches/reads
   - Use only 1 Sonnet subagent for build/tests (backpressure)
   - Use Opus subagents when complex reasoning is needed (debugging, architecture)

   If functionality is missing, add it per the specifications. Ultrathink.

### Incremental Development Rule

When creating multiple files (tests, modules, components):

1. **Write ONE file**
2. **Run verification** (test, compile, lint)
3. **Fix any failures**
4. **Commit checkpoint** (optional but recommended)
5. **Move to next file**

**NEVER write multiple files without verification between them.**

This prevents "batch-and-pray" development where 5 files are written and all fail simultaneously, making debugging exponentially harder.

## Definition of Done

Acceptance criteria with verification commands (e.g., "tests pass", "builds successfully") **MUST be verified locally** before marking complete.

**"Syntax check" is NOT verification.**
**"CI will run it" is NOT verification.**
**"Files exist" is NOT verification.**

If verification is impossible:
1. **ATTEMPT** to fix the environment (install tools, create venv, configure paths)
2. If still blocked, **CREATE A BLOCKING ISSUE** explaining why verification failed
3. **DO NOT** mark the task complete

---

## Acceptance Criteria Integrity

You **MUST NOT** reinterpret acceptance criteria during implementation:
- "tests pass" means tests **PASS**, not "tests exist" or "tests pending CI"
- "builds successfully" means build **SUCCEEDS**, not "syntax valid"
- "no lint errors" means lint **RUNS AND PASSES**, not "linter not available"

### Invalid Verification Shortcuts (PROHIBITED)

| AC Says | Invalid Shortcut | Why It's Wrong |
|---------|------------------|----------------|
| "tests pass" | "syntax is valid" | Syntax check doesn't execute tests |
| "tests pass" | "code looks correct" | Visual inspection isn't verification |
| "tests pass" | "CI will run it" | Defers verification, breaks the loop |
| "builds successfully" | "no syntax errors" | Compile ≠ syntax check |
| "lint passes" | "linter not installed" | Environment issue, not completion |

### Handling Missing Test Dependencies

When tests cannot run due to missing dependencies:

1. **In sandbox environments**: Attempt to install dependencies
   - `pip install <pkg>`, `npm install`, `cargo install`, etc.
   - Check for requirements.txt, package.json, Cargo.toml

2. **If installation fails**: Create a blocking issue
   ```bash
   bd create --title="Blocker: Missing <dep> for tests" --type=bug --priority=1 \
     --description="Cannot verify <task-id>: <dependency> missing.
   Tried: <what you tried>
   Error: <error message>"
   bd dep add <original-task> <new-blocker-id>
   ```

3. **Move to next ready task** - don't close with unverified AC

If you cannot verify a criterion as written:
1. The task is **BLOCKED**, not complete
2. Create a blocking issue documenting why verification failed
3. Move to next available task (`bd ready`)

**NEVER lower the bar to close a task.**

### ⚠️ Completion Bias Warning

You will feel a pull toward marking tasks "done" - especially when you're in a flow state closing multiple tasks. This is **completion bias**.

Signs you're rationalizing:
- "The infrastructure is complete" (but AC says deliver X, not infrastructure for X)
- "I documented the gap in the close reason" (documentation ≠ completion)
- "It's mostly done" (partial ≠ done)
- "The hard part is finished" (hard part done ≠ AC satisfied)

If you catch yourself thinking "close enough" → **STOP**. The task is BLOCKED, not complete. The beads graph depends on accurate state. Future sessions and other agents will trust your close reason.

### Handling Tasks Requiring External Resources

Some tasks require resources you cannot produce (external datasets, API keys, human review, physical hardware, etc.).

**Pattern: Label as `manual` and document what's needed**

```bash
# Add the manual label
bd label add <id> manual

# Document what was done vs what remains
bd comments add <id> "
BLOCKED - Requires manual intervention:
- Completed: [what you built]
- Remaining: [what requires human action]
- Next steps: [specific instructions for human]
"

# Update notes for visibility
bd update <id> --notes "MANUAL: [brief description of what's needed]"
```

**Do NOT close tasks requiring manual intervention.** Leave them open with the `manual` label so they appear in filtered queries and humans know action is needed.

Example scenarios:
- Task requires audio samples from external datasets → label `manual`, document sourcing instructions
- Task requires API credentials → label `manual`, document which credentials and where to configure
- Task requires human review/approval → label `manual`, document what to review

---

## Phase 3: Validate Against Acceptance Criteria

3. **For EACH criterion in the acceptance criteria**:

   a. Run the verification command and capture the result:
      ```bash
      # Example: Run the test
      npm test src/auth.test.ts
      echo "Exit code: $?"
      ```

   b. **If it passes**: Move to next criterion

   c. **If it fails with a trivial fix** (typo, syntax, <10 lines): Fix inline

   d. **If it fails requiring substantial work**: Create a blocking issue:
      ```bash
      # If RALPH_SCOPE is set, use --parent=${RALPH_SCOPE}; otherwise use --parent=<epic-if-applicable>
      bd create --title="Fix: [specific failure]" --type=bug --priority=1 \
        --parent=<epic-or-RALPH_SCOPE> \
        --description="
      ## Context
      Discovered while validating <current-id>

      ## Failure Details
      - Command: [what was run]
      - Expected: [what should happen]
      - Actual: [what happened]

      ## References
      - path/to/failing/test.ts
      " \
        --acceptance="- [ ] [Specific test] passes | \`[command]\` | exit 0"

      bd dep add <current-id> <new-bug-id>
      bd update <current-id> --notes "Blocked by <new-bug-id>: [brief description]"
      ```
      Then move to next ready task.

   e. Document any criterion marked `MANUAL` with your verification notes.

## Phase 4: Handle Discovered Work

4. **If you discover issues during implementation**:
   ```bash
   # If RALPH_SCOPE is set (see top of file), include --parent=${RALPH_SCOPE}
   bd create --title="Discovered: [issue]" --type=bug --priority=2 \
     --parent=<RALPH_SCOPE-if-set> \
     --description="Found while working on <current-id>" \
     --acceptance="- [ ] [Specific fix] | \`[command]\` | exit 0"
   ```

   **You MAY**:
   - Create new issues (discovered work)
   - Add dependencies (found new blocker)

   **You CANNOT remove dependencies or modify structure** (requires PLANNING mode):
   - Remove dependencies
   - Change priorities
   - Modify acceptance criteria
   - Delete issues

## Phase 5: Complete Task

5. **Only when ALL acceptance criteria are verified**:

   ```bash
   # Verify all criteria one more time
   bd show <id> --json | jq -r '.[0].acceptance_criteria'
   # Run all verification commands, confirm all pass

   # Close with evidence
   bd close <id> --reason "
   Verified:
   - [x] [criterion 1] - [command] exit 0
   - [x] [criterion 2] - [command] exit 0
   - [x] [criterion 3] - MANUAL reviewed
   "

   # Commit
   git add -A
   git commit -m "[<id>] [description of what was implemented]"
   ```

## Guardrails (in order of importance)

999. Required tests derived from acceptance criteria must exist and pass before committing.
     Tests are part of implementation scope, not optional.

9999. Capture the WHY in close reasons — future iterations depend on this context.

99999. Keep notes updated during work:
       ```bash
       bd update <id> --notes "Learning: [insight discovered]"
       ```

999999. If stuck for >3 attempts, add detailed notes and move to next ready task:
        ```bash
        bd update <id> --notes "STUCK: [detailed explanation of blocker]"
        ```
        The loop will detect this and move on.

9999999. NEVER remove dependencies, change priorities, or modify acceptance criteria.
         These structural changes require PLANNING mode review.

99999999. Implement functionality completely. Placeholders and stubs waste effort.

999999999. For bugs noticed but unrelated to current work, file them:
           ```bash
           # If RALPH_SCOPE is set (see top of file), include --parent=${RALPH_SCOPE}
           bd create --title="Bug: [description]" --type=bug --priority=2 \
             --parent=<RALPH_SCOPE-if-set> \
             --acceptance="- [ ] [Fix verification] | \`[command]\` | exit 0"
           ```

9999999999. When you learn operational details, update @AGENTS.md but keep it brief.
            A bloated AGENTS.md pollutes every future loop's context.

99999999999. If tests unrelated to your work fail, resolve them as part of the increment.
             Single sources of truth, no broken windows.

999999999999. When you find inconsistencies in requirements (specs/* or epic descriptions), note them for PLANNING mode:
              ```bash
              bd create --title="Requirement inconsistency: [description]" --type=task --priority=3
              ```
