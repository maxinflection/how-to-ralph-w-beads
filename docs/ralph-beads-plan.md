# how-to-ralph-w-beads Implementation Plan

## Vision

A fork of how-to-ralph-wiggum that replaces markdown-based planning artifacts (`IMPLEMENTATION_PLAN.md`, `specs/*`) with well-structured Beads epics and issues. The key innovation is using Beads' dependency graph and acceptance criteria fields to provide **verifiable exit conditions** that prevent infinite loops while maintaining Ralph's "eventual consistency through iteration" philosophy.

---

## Core Transformation Mapping

| Ralph Original | Beads Replacement |
|----------------|-------------------|
| `IMPLEMENTATION_PLAN.md` | `bd ready` queue + dependency graph |
| `specs/*.md` | Beads epics with child issues |
| "Task" in markdown plan | Beads issue (task/feature/bug) |
| "Topic of Concern" | Beads epic |
| "JTBD" | Top-level epic or label |
| Gap analysis output | `bd list --status open` |
| "Most important task" | `bd ready --limit 1 --sort priority` |

---

## Project Structure

```
how-to-ralph-w-beads/
├── README.md                    # Overview + philosophy
├── QUICKSTART.md               # 5-minute setup guide
├── .beads/                     # Initialized beads database
│   └── issues.jsonl            # Example issues for learning
├── files/
│   ├── loop.sh                 # Enhanced loop script
│   ├── PROMPT_plan.md          # Planning mode (creates beads)
│   ├── PROMPT_build.md         # Building mode (implements from beads)
│   ├── AGENTS.md               # Template with beads workflow
│   └── CLAUDE.md               # Template for Claude projects
├── docs/
│   ├── ACCEPTANCE_CRITERIA.md  # Standards for verifiable AC
│   ├── LOOP_CONTROL.md         # How exit conditions work
│   ├── EPIC_STRUCTURE.md       # How to structure epics/issues
│   └── MIGRATION.md            # Converting existing Ralph projects
├── examples/
│   ├── jtbd-to-epic/           # Example: JTBD → Epic conversion
│   ├── feature-breakdown/      # Example: Feature → Issues
│   └── acceptance-patterns/    # Example: AC patterns by type
└── references/
    └── (diagrams, images)
```

---

## Phase 1: Core Artifacts

### 1.1 Enhanced loop.sh

```bash
#!/bin/bash
# Usage: ./loop.sh [plan|build] [max_iterations]

MODE="${1:-build}"
MAX_ITERATIONS="${2:-0}"
ITERATION=0

# Ensure beads is initialized
if [ ! -d ".beads" ]; then
    echo "Initializing beads..."
    bd init --quiet
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode: $MODE | Max: ${MAX_ITERATIONS:-unlimited}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    # Exit condition: max iterations
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
        echo "✓ Reached max iterations: $MAX_ITERATIONS"
        break
    fi
    
    # Exit condition: no ready work (build mode only)
    if [ "$MODE" = "build" ]; then
        READY_COUNT=$(bd ready --json 2>/dev/null | jq 'length // 0')
        if [ "$READY_COUNT" -eq 0 ]; then
            echo "✓ No ready work remaining - loop complete"
            break
        fi
    fi
    
    # Run iteration
    cat "PROMPT_${MODE}.md" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose
    
    # Sync beads and push
    bd sync
    git push origin "$(git branch --show-current)" 2>/dev/null || \
        git push -u origin "$(git branch --show-current)"
    
    ITERATION=$((ITERATION + 1))
    echo -e "\n═══════════ LOOP $ITERATION ═══════════\n"
done

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Loop finished after $ITERATION iterations"
bd stats
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### 1.2 PROMPT_plan.md (Beads-Integrated)

```markdown
# PLANNING MODE - Triage Stuck Work + Generate New Issues

0a. Run `bd ready` and `bd list --status open` to understand current work state.
0b. Study `specs/*` with up to 25 parallel Sonnet subagents to learn requirements.
0c. Study existing source code to understand patterns and utilities.

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
      - If dependency was wrong → Remove it (only planning mode can do this)
      - If obsolete → Delete or close as won't-fix

2. **Review manually-blocked issues** (status=blocked, external blockers):
   ```bash
   bd list --status blocked --json
   ```
   These are issues blocked by external factors (not beads dependencies).
   For each, read notes to understand the blocker:
   
   a. **If blocker is resolved** (e.g., vendor delivered, decision made):
      ```bash
      bd update <id> --status open --notes "Unblocked: [what changed]"
      ```
   
   b. **If blocker can now be modeled as beads work** (e.g., we now understand 
      what's needed): Create the blocking issue and add dependency:
      ```bash
      bd create "Prerequisite: [what's needed]" --type task --priority 1 \
        --description "## Context\nRequired to unblock <id>" \
        --acceptance "- [ ] [Specific deliverable]"
      bd dep add <blocked-id> <new-prereq-id>
      bd update <blocked-id> --status open --notes "Now tracked via dependency on <new-prereq-id>"
      ```
   
   c. **If still externally blocked**: Leave as-is, update notes with current status

   NOTE: Issues blocked by beads dependencies auto-unblock when blockers close.
   The `--status blocked` is reserved for external blockers only.

## Phase 2: Gap Analysis and New Work

3. **Gap Analysis**: Compare specs against existing code and beads issues.
   Use up to 50 Sonnet subagents to search codebase.
   For each gap identified:
   
   a. Check if a beads issue already exists: `bd list --title-contains "keyword"`
   b. If not, create an epic or issue with VERIFIABLE acceptance criteria:
   
   ```bash
   bd create "Epic: [Topic]" --type epic --priority 1 \
     --description "## Context\n[Why this work exists]\n\n## Scope\n[What's included]" \
     --acceptance "- [ ] [Specific, testable criterion 1]\n- [ ] [Measurable outcome 2]"
   # Returns: bd-a1b2 (epic ID)
   ```
   
   c. Create child tasks under the epic:
   ```bash
   bd create "Implement [specific thing]" --type task --priority 2 \
     --parent bd-a1b2 \
     --description "## References\n- path/to/file.ts\n\n## Approach\n[Implementation notes]" \
     --acceptance "- [ ] Unit tests pass\n- [ ] Integration test for [scenario]"
   # Returns: bd-a1b2.1 (hierarchical child ID)
   ```
   
   d. Add blocking dependencies between siblings (if task B requires task A):
   ```bash
   bd dep add bd-a1b2.2 bd-a1b2.1  # Task 2 blocked by Task 1
   ```

4. **Dependency Wiring**: Ensure all blocking relationships are captured.
   ```bash
   bd dep tree <epic-id>  # Visualize and verify
   bd dep cycles          # Check for cycles
   ```

5. **Priority Assignment**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog

IMPORTANT: Plan only. Do NOT implement. Every issue MUST have:
- Verifiable acceptance criteria (not vague outcomes)
- Clear dependencies on blocking work
- Reference to relevant spec or code location

ULTIMATE GOAL: `bd ready` should show a prioritized queue of implementable work,
with no stuck issues lingering and all blocked work properly tracked.
```

### 1.3 PROMPT_build.md (Beads-Integrated)

```markdown
# BUILDING MODE - Implement from Beads Queue

0a. Run `bd ready --json | jq '.[0]'` to get the highest-priority unblocked task.
0b. Run `bd show <id>` to read full context, acceptance criteria, and dependencies.
0c. Study referenced files and existing code for patterns.

1. **Claim Work**: 
   ```bash
   bd update <id> --status in_progress
   ```

2. **Implement**: Use up to 50 parallel Sonnet subagents for searches/reads.
   Use only 1 Sonnet subagent for build/tests (backpressure).
   
   CRITICAL: Before writing code, search first - don't assume not implemented.

3. **Validate Against Acceptance Criteria**:
   For EACH criterion in the issue's acceptance criteria:
   - Run the specified test/check
   - If it fails with a trivial fix (typo, syntax, few lines): fix inline
   - If it fails requiring substantial work: create a new blocking issue:
     ```bash
     bd create "Fix: [specific failure]" --type bug --priority 1 \
       --parent <epic-if-applicable> \
       --description "## Context\nDiscovered while validating <current-id>\n\n## References\n- path/to/failing/test.ts\n- Error output: [summary]" \
       --acceptance "- [ ] [Specific test/check] passes"
     bd dep add <current-id> <new-bug-id>  # Current task now blocked
     bd update <current-id> --status blocked --notes "Blocked by <new-bug-id>"
     ```
   - Document any criterion that cannot be verified automatically

4. **Discovered Work**: If you find new issues during implementation:
   ```bash
   bd create "Discovered: [issue]" --type bug --priority 1
   bd dep add <new-id> <current-id> --type discovered-from
   ```
   
   NOTE: You may ADD dependencies (discovered blockers) but NEVER remove them.
   Dependency removal requires PLANNING mode review.

5. **Complete Task**:
   ```bash
   # Only when ALL acceptance criteria are met:
   bd close <id> --reason "[What was implemented, which tests verify it]"
   git add -A && git commit -m "[<id>] [description]"
   ```

99999. Important: Capture the WHY in close reasons - future iterations depend on this.
999999. Keep notes updated: `bd update <id> --notes "Learning: [insight]"`
9999999. If stuck for >3 attempts, add detailed notes and move to next ready task.
99999999. NEVER remove dependencies, change priorities, or modify acceptance criteria.
         These structural changes require PLANNING mode.
```

---

## Phase 2: Acceptance Criteria Standards

### 2.1 ACCEPTANCE_CRITERIA.md

```markdown
# Acceptance Criteria Standards for Ralph+Beads

## The Problem
Ralph loops can run forever if exit conditions are vague. Acceptance criteria 
MUST be **verifiable** - either programmatically or by explicit LLM-as-judge.

## Required Properties

Every acceptance criterion must be:

1. **Specific** - Names exact behavior, not vague quality
   - ❌ "Code is clean"
   - ✅ "No lint errors from `npm run lint`"

2. **Measurable** - Has a binary pass/fail check
   - ❌ "Performance is good"
   - ✅ "Response time < 200ms for 95th percentile"

3. **Automatable** - Can be verified by running a command
   - ❌ "UI looks correct"
   - ✅ "Playwright visual regression test passes" OR
   - ✅ "LLM-as-judge confirms layout matches spec (see criterion-ui-check.md)"

## Acceptance Criteria Patterns

### Pattern 1: Test-Backed (Preferred)
```
- [ ] `npm test src/auth.test.ts` passes
- [ ] `npm run e2e -- --grep "login flow"` passes  
- [ ] `npm run typecheck` reports 0 errors
```

### Pattern 2: Command Output
```
- [ ] `curl localhost:3000/health` returns {"status":"ok"}
- [ ] `wc -l src/utils.ts` is < 500 (file size limit)
- [ ] `grep -r "TODO" src/` returns empty (no TODOs)
```

### Pattern 3: LLM-as-Judge (For Subjective Criteria)
```
- [ ] LLM review confirms: "Error messages are user-friendly, not technical jargon"
      Artifact: error-messages.md
      Criteria: Each message (1) explains what went wrong, (2) suggests action
```

### Pattern 4: Existence Checks
```
- [ ] File exists: src/components/Button.tsx
- [ ] Export exists: `grep "export.*Button" src/components/index.ts`
- [ ] Route registered: `grep "/api/users" src/routes.ts`
```

## Anti-Patterns (NEVER Use)

| Anti-Pattern | Why It Fails | Better Alternative |
|--------------|--------------|-------------------|
| "Works correctly" | Unfalsifiable | Specific test case |
| "Handles edge cases" | Unbounded scope | List exact cases |
| "Good performance" | No threshold | Specific metric |
| "Clean code" | Subjective | Lint/format check |
| "User-friendly" | Vague | LLM-as-judge with rubric |

## Verifying Criteria in Build Mode

The BUILDING prompt includes this validation step:

```bash
# For each criterion, the agent must either:

# 1. Run the command and capture output
npm test src/auth.test.ts
# Check: exit code 0 = pass

# 2. For LLM-as-judge criteria, document explicitly:
# "Verified: Error messages are user-friendly per LLM review [timestamp]"
```

## Exit Condition Logic

The loop exits when:
1. `bd ready` returns empty (no unblocked work), OR
2. Max iterations reached, OR
3. Agent explicitly signals completion with all AC verified
```

---

## Phase 3: Loop Control Mechanisms

### 3.1 LOOP_CONTROL.md

```markdown
# Loop Control: Preventing Infinite Iterations

## The Ralph Challenge
Ralph's power comes from persistence - but unchecked persistence wastes resources.
Beads provides three natural exit conditions:

## Exit Condition 1: Empty Ready Queue

```bash
# In loop.sh
READY_COUNT=$(bd ready --json | jq 'length')
if [ "$READY_COUNT" -eq 0 ]; then
    echo "✓ All work complete or blocked"
    exit 0
fi
```

This triggers when:
- All issues are closed
- All open issues are blocked by other open issues
- No unblocked P0-P4 work exists

## Exit Condition 2: Acceptance Criteria Satisfaction

Each task's acceptance criteria form a checklist. The agent MUST verify each
before calling `bd close`. This prevents "false done" states.

```bash
# In PROMPT_build.md, step 5:
# "Only close when ALL acceptance criteria are met"

bd close <id> --reason "
Acceptance criteria verified:
- [x] Unit tests pass (npm test auth.test.ts - exit 0)
- [x] Integration test passes (npm run e2e login - exit 0)  
- [x] TypeScript compiles (tsc --noEmit - exit 0)
"
```

## Exit Condition 3: Max Iterations (Safety Valve)

```bash
./loop.sh build 50  # Maximum 50 iterations
```

When max iterations hit:
1. Loop stops gracefully
2. Current work state preserved in beads
3. Human reviews `bd list --status in_progress` for stuck work

## Stuck Detection

If same issue stays `in_progress` for >3 iterations:

```bash
# Agent should add note explaining WHY it's stuck
bd update <id> --notes "Stuck after 3 attempts: [specific blocker reason]"

# DO NOT deprioritize or remove dependencies in build mode!
# Instead, move to next ready task and let planning mode triage
```

The PLANNING loop will later review stuck issues and decide whether to:
- Adjust priority
- Add/remove dependencies  
- Split into smaller issues
- Mark as blocked pending external input

## Preventing Circumvention

The acceptance criteria model prevents gaming because:

1. **Criteria are written during PLANNING** (before implementation)
2. **Criteria reference specific commands** (not subjective assessment)
3. **Close reasons must cite which criteria were verified**
4. **Audit trail in beads** tracks all changes

### Separation of Powers (Critical)

**BUILD mode can:**
- ✅ Create new issues (discovered work)
- ✅ Add dependencies (found new blocker)
- ✅ Update status (open → in_progress → closed)
- ✅ Add notes and update descriptions
- ✅ Close issues (with verified acceptance criteria)

**BUILD mode CANNOT:**
- ❌ Remove dependencies
- ❌ Change priority
- ❌ Delete issues
- ❌ Modify acceptance criteria
- ❌ Change issue type

**Only PLANNING mode can:**
- ✅ Remove dependencies (after analysis)
- ✅ Adjust priorities (based on new information)
- ✅ Modify acceptance criteria (refine scope)
- ✅ Delete/archive issues (obsolete work)
- ✅ Restructure epic/task relationships

This separation ensures the build agent cannot "game" its way out of
difficult work by simply removing blockers or deprioritizing everything.
The planning loop acts as a checkpoint that requires deliberate human
or planning-mode review before structural changes.
```

---

## Phase 4: AGENTS.md Template

```markdown
# AGENTS.md - Project Operational Guide

## Issue Tracking with Beads

This project uses `bd` (beads) for issue tracking. ALL work flows through beads.

### Starting a Session

```bash
# 1. Orient yourself
bd ready                    # What's available to work on
bd list --status in_progress  # What's already claimed

# 2. Pick highest-priority ready task
TASK=$(bd ready --json | jq -r '.[0].id')
bd show $TASK              # Read full context

# 3. Claim it
bd update $TASK --status in_progress
```

### During Implementation

```bash
# Discovered new work? File it immediately
bd create "Found: [issue]" --type bug --priority 1 \
  --description "Discovered while working on $TASK"
bd dep add <new-id> $TASK --type discovered-from

# Learning something? Capture it
bd update $TASK --notes "Insight: [what you learned]"
```

### Completing Work

```bash
# ONLY when all acceptance criteria verified:
bd show $TASK  # Review acceptance criteria one more time

# Close with evidence
bd close $TASK --reason "
Verified:
- [x] [criterion 1] - [how verified]
- [x] [criterion 2] - [how verified]
"

# Commit
git add -A
git commit -m "[$TASK] [what was done]"
```

### Ending a Session

1. Update any in-progress work with notes
2. File issues for anything discovered but not addressed
3. Run `bd sync` to ensure database is current
4. Push all changes

### Creating Good Issues

```bash
bd create "Descriptive title" \
  --type task \
  --priority 2 \
  --description "
## Context
Why this work matters.

## References  
- path/to/relevant/file.ts
- Link to spec or design doc

## Approach
1. Step one
2. Step two
" \
  --acceptance "
- [ ] Specific verifiable criterion 1
- [ ] Command-based check: \`npm test file.test.ts\`
- [ ] Existence check: File src/new-thing.ts exists
"
```

### Dependency Management

```bash
# A depends on B (B blocks A)
bd dep add A B

# View dependency tree
bd dep tree A

# Check for cycles (should be empty)
bd dep cycles
```

### ⚠️ Build Mode Restrictions

During BUILD mode (implementation), you may NOT:
- Remove dependencies (`bd dep remove` is FORBIDDEN)
- Change priorities (`bd update --priority` is FORBIDDEN)
- Modify acceptance criteria (`bd update --acceptance` is FORBIDDEN)
- Delete issues (`bd delete` is FORBIDDEN)

These structural changes require switching to PLANNING mode, which ensures
deliberate review before altering the work graph. This prevents "gaming"
the system by removing blockers instead of solving them.

If you're stuck, add notes explaining why and move to the next ready task.
Planning mode will triage stuck issues later.

## Build & Test Commands

[Project-specific commands here]

```bash
npm install        # Install dependencies
npm run build      # Build project
npm test           # Run all tests
npm run lint       # Check code style
npm run typecheck  # TypeScript validation
```
```

---

## Phase 5: Migration Guide

### MIGRATION.md

```markdown
# Migrating Existing Ralph Projects to Beads

## From IMPLEMENTATION_PLAN.md

Your markdown plan:
```markdown
- [ ] P1: Implement user auth
  - [ ] Add login endpoint
  - [ ] Add logout endpoint
- [ ] P2: Add dashboard
```

Becomes beads issues:
```bash
# Create epic
bd create "User Authentication" --type epic --priority 1
# Returns: bd-a1b2

# Create tasks as children of the epic
bd create "Add login endpoint" --type task --priority 1 \
  --parent bd-a1b2 \
  --acceptance "- [ ] POST /auth/login returns JWT\n- [ ] Invalid creds return 401"
# Returns: bd-a1b2.1

bd create "Add logout endpoint" --type task --priority 1 \
  --parent bd-a1b2 \
  --acceptance "- [ ] POST /auth/logout invalidates session\n- [ ] Returns 200"
# Returns: bd-a1b2.2

# Wire blocking dependency between siblings (logout depends on login existing)
bd dep add bd-a1b2.2 bd-a1b2.1
```

## From specs/*.md

Each spec file becomes an epic:
```bash
# Read spec
cat specs/auth.md

# Create epic with spec content
bd create "Auth System" --type epic --priority 1 \
  --description "$(cat specs/auth.md)" \
  --acceptance "- [ ] All child tasks complete\n- [ ] Integration tests pass"
```

## Automation Script

```bash
#!/bin/bash
# migrate-plan.sh - Convert IMPLEMENTATION_PLAN.md to beads

# This is a starting point - customize for your plan format
grep -E "^- \[ \]" IMPLEMENTATION_PLAN.md | while read -r line; do
    # Extract priority (P0, P1, P2, etc)
    PRIORITY=$(echo "$line" | grep -oE "P[0-4]" | sed 's/P//')
    PRIORITY=${PRIORITY:-2}  # Default P2
    
    # Extract title
    TITLE=$(echo "$line" | sed 's/^- \[ \] //' | sed 's/P[0-4]: //')
    
    bd create "$TITLE" --type task --priority "$PRIORITY"
done
```
```

---

## Implementation Checklist

- [ ] Fork how-to-ralph-wiggum repository
- [ ] Remove/archive original markdown-based files
- [ ] Create new directory structure per plan
- [ ] Write loop.sh with beads integration and exit conditions
- [ ] Write PROMPT_plan.md for beads-based planning
- [ ] Write PROMPT_build.md for beads-based building
- [ ] Write ACCEPTANCE_CRITERIA.md standards document
- [ ] Write LOOP_CONTROL.md explaining exit mechanisms
- [ ] Write AGENTS.md template
- [ ] Write CLAUDE.md template
- [ ] Create example issues in .beads/
- [ ] Write migration guide
- [ ] Test full workflow end-to-end
- [ ] Write README.md with philosophy and quickstart

---

## Key Differentiators from Original Ralph

| Aspect | Original Ralph | Ralph + Beads |
|--------|---------------|---------------|
| Plan format | Markdown | Structured JSON (beads) |
| Dependencies | Implicit in text | Explicit graph edges |
| Ready work | Parse markdown | `bd ready` query |
| Exit condition | Manual/iteration limit | Empty queue + AC verified |
| Audit trail | Git history | Beads audit log |
| Multi-agent | Conflict-prone | Hash IDs, merge-safe |
| Acceptance | Informal | Mandatory, verifiable |
| Stuck detection | Manual observation | Query `in_progress` duration |
