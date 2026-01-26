# PLANNING MODE - Triage Stuck Work + Generate New Issues

<!-- RALPH_SCOPE: ${RALPH_SCOPE} -->

## Phase 0: Orient

**0a. Understand current work state:**
- If RALPH_SCOPE is set above (non-empty): Run `bd ready --parent=${RALPH_SCOPE}` and `bd list --status open --parent=${RALPH_SCOPE}`
- Otherwise: Run `bd ready` and `bd list --status open`

This shows current work (within scope if scoped).

0b. **Determine requirements source** (specs are optional):
    - If `specs/*` exists and has files → Study specs as the source of truth
    - If no specs exist → Use beads epics as the source of truth:
      ```bash
      # List all epics and their descriptions
      bd list --type epic --json | jq '.[] | {id, title, description}'
      ```

    Study the requirements source with up to 25 parallel Sonnet subagents.

0c. Study existing source code in `src/*` with up to 25 parallel Sonnet subagents to understand patterns and utilities.
0d. Study `src/lib/*` (if present) to understand shared utilities & components.

## Phase 1: Triage Stuck and Blocked Work

1. **Review stuck issues** (in_progress but not progressing):
   ```bash
   bd list --status in_progress --json
   ```
   For each, read the notes field. If notes indicate repeated failures:

   a. **Analyze root cause**: Is it blocked by missing dependency? Too large?
      Unclear acceptance criteria? External blocker?

   b. **Take action**:
      - If too large → Split into smaller issues with clearer scope
      - If missing dependency → Add the dependency, create blocking issue if needed
      - If acceptance criteria unclear → Refine them to be more specific/testable
      - If external blocker → Mark status as `blocked`, add note explaining what's needed
      - If dependency was wrong → Remove it (only PLANNING mode can do this)
      - If obsolete → Close with reason explaining why

2. **Review blocked issues** (blocked by dependencies or external factors):
   ```bash
   bd blocked
   ```
   For each, understand what's blocking it:

   a. **If blocker is resolved** (dependency closed, external blocker cleared):
      The issue should auto-unblock. If not, check dependency graph.

   b. **If blocker can now be modeled as beads work**:
      ```bash
      # If RALPH_SCOPE is set (see top of file), include --parent=${RALPH_SCOPE}
      bd create --title="Prerequisite: [what's needed]" --type=task --priority=1 \
        --parent=<RALPH_SCOPE-if-set> \
        --description="## Context\nRequired to unblock <blocked-id>" \
        --acceptance="- [ ] [Specific deliverable] | \`[command]\` | exit 0"
      bd dep add <blocked-id> <new-prereq-id>
      ```

   c. **If still blocked by external factors**: Update notes with current status.

## Phase 2: Gap Analysis and New Work

3. **Gap Analysis**: Compare requirements (specs OR epics) against existing code and beads issues.
   Use up to 50 Sonnet subagents to search the codebase.

   **If using epics as source of truth**: The epic descriptions define the requirements.
   Create child tasks for each epic based on its scope and success criteria.

   For each gap identified:

   a. Check if a beads issue already exists:
      ```bash
      bd search "keyword"
      bd list --json | jq '.[] | select(.title | contains("keyword"))'
      ```

   b. If not, create an epic or issue with VERIFIABLE acceptance criteria:

   **For Epics** (large bodies of work with multiple tasks):
   ```bash
   # If RALPH_SCOPE is set, new epics should be children of that scope
   # Otherwise, create top-level epics
   bd create --title="Epic: [Topic]" --type=epic --priority=1 \
     --parent=<RALPH_SCOPE-if-set> \
     --description="
   ## Context
   [Why this work exists]

   ## Scope
   [What's included]

   ## Success Criteria
   [What does done look like for this epic?]
   "
   # Note: Epics don't need --acceptance; their children define the work
   ```

   **For Tasks** (implementable units of work):
   ```bash
   # If RALPH_SCOPE is set, use --parent=${RALPH_SCOPE} (or child epic)
   bd create --title="Implement [specific thing]" --type=task --priority=2 \
     --parent=<epic-id-or-RALPH_SCOPE> \
     --description="
   ## Context
   [Why this task exists]

   ## References
   - path/to/file.ts
   - docs/relevant-doc.md

   ## Approach
   [Implementation notes or pseudo-code]
   " \
     --acceptance="
   - [ ] Unit tests pass | \`npm test path/to/test.ts\` | exit 0
   - [ ] No lint errors | \`npm run lint -- path/to/\` | exit 0
   - [ ] Build succeeds | \`npm run build\` | exit 0
   "
   ```

   c. **Derive test requirements from acceptance criteria**:
      - What behavior needs testing? → Unit test criterion
      - What integration points? → Integration test criterion
      - What error cases? → Error handling criteria
      - What commands verify success? → Include exact commands

   d. Add blocking dependencies between related tasks:
      ```bash
      bd dep add <task-that-waits> <task-that-blocks>
      ```

4. **Dependency Wiring**: Ensure all blocking relationships are captured.
   ```bash
   bd list --json | jq '.[] | {id, title, blockedBy}'
   ```
   Check for:
   - Tasks that logically depend on each other but aren't linked
   - Circular dependencies (bd will warn about these)

5. **Priority Assignment**:
   - P0: Critical blockers, production issues
   - P1: High priority, core functionality
   - P2: Medium priority, important but not urgent
   - P3: Low priority, nice to have
   - P4: Backlog, future consideration

## Guardrails

IMPORTANT: Plan only. Do NOT implement anything.

Every issue MUST have:
- Verifiable acceptance criteria (not vague outcomes)
- Clear dependencies on blocking work
- Reference to relevant spec or code location

Acceptance criteria format (see docs/ACCEPTANCE_CRITERIA.md for full patterns):
```
- [ ] {description} | `{verification_command}` | {expected_outcome}
```

Examples:
- [ ] Login returns JWT | `npm test -- --grep "login"` | exit 0
- [ ] Endpoint responds | `curl -s localhost:3000/health` | {"status":"ok"}
- [ ] File exists | `test -f src/auth/index.ts` | exit 0

Do NOT assume functionality is missing; confirm with code search first.

Treat `src/lib` as the project's standard library. Prefer consolidated implementations there.

## Ultimate Goal

After planning, `bd ready` should show a prioritized queue of implementable work with:
- No stuck issues lingering
- All blocked work properly tracked with dependencies
- All issues having verifiable acceptance criteria
- Clear path from current state to completion

Run `bd stats` to verify project health before ending.
