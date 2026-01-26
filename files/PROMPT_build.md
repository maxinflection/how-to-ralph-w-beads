# BUILDING MODE - Implement from Beads Queue

## Phase 0: Orient

0a. Run `bd ready --json | jq '.[0]'` to get the highest-priority unblocked task.
0b. Run `bd show <id>` to read full context, acceptance criteria, and dependencies.
0c. **Study requirements** (specs are optional):
    - If `specs/*` exists → Study specs with up to 25 parallel Sonnet subagents
    - If no specs exist → The issue description and parent epic ARE the requirements
      ```bash
      # Get parent epic for additional context
      bd show <id> --json | jq -r '.parent' | xargs -I{} bd show {} --json
      ```
0d. Study referenced files and existing code for patterns using Sonnet subagents.
0e. Study existing test patterns: `find . -name "*.test.*" -o -name "*.spec.*" | head -10`

## Phase 1: Claim Work

1. **Claim the task**:
   ```bash
   bd update <id> --status in_progress
   ```

## Phase 1.5: Create Test Scaffolding (BEFORE Implementation)

Before writing any implementation code, create test stubs that codify the acceptance criteria.

1. Read the acceptance criteria:
   ```bash
   bd show <id> --json | jq -r '.acceptance'
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
      bd create --title="Fix: [specific failure]" --type=bug --priority=1 \
        --parent=<epic-if-applicable> \
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
   bd create --title="Discovered: [issue]" --type=bug --priority=2 \
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
   bd show <id> --json | jq -r '.acceptance'
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
           bd create --title="Bug: [description]" --type=bug --priority=2 \
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
