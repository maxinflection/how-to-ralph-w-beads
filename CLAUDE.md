# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**how-to-ralph-w-beads** (htrwb) - A fork of [ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook) that replaces markdown-based planning artifacts with [beads](https://github.com/steveyegge/beads) structured issue tracking. The key innovation is using beads' dependency graph and verifiable acceptance criteria to provide **deterministic exit conditions** that prevent infinite loops while maintaining Ralph's "eventual consistency through iteration" philosophy.

## Core Transformation

| Ralph Original | Beads Replacement |
|----------------|-------------------|
| `IMPLEMENTATION_PLAN.md` | `bd ready` queue + dependency graph |
| `specs/*.md` | Beads epics with child issues |
| "Task" in markdown plan | Beads issue (task/feature/bug) |
| "Topic of Concern" | Beads epic |
| Gap analysis output | `bd list --status open` |
| "Most important task" | `bd ready --limit 1 --sort priority` |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Ralph Loop (loop.sh)                        │
├─────────────────────────────────────────────────────────────────┤
│  PLAN Mode                 │  BUILD Mode                        │
│  ─────────────────────     │  ──────────────────────────────    │
│  - Gap analysis            │  - Pick from bd ready              │
│  - Create/refine issues    │  - Implement with tests first      │
│  - Wire dependencies       │  - Validate acceptance criteria    │
│  - Set priorities          │  - Close with verification         │
│  - CAN modify AC           │  - CAN add dependencies            │
│  - CAN remove deps         │  - CANNOT remove deps/modify AC    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Beads Issue Graph                            │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                │
│  │  Epic    │────▶│  Task    │────▶│  Task    │                │
│  │ bd-a1b2  │     │ bd-a1b2.1│     │ bd-a1b2.2│ (blocked by .1)│
│  └──────────┘     └──────────┘     └──────────┘                │
│       │                │                                        │
│       │           Acceptance Criteria                           │
│       │           ─────────────────                             │
│       │           - [ ] Tests pass: `npm test feat.test.ts`     │
│       │           - [ ] Lint clean: `npm run lint`              │
│       ▼                                                         │
│  Exit Condition: bd ready returns empty                         │
└─────────────────────────────────────────────────────────────────┘
```

## Key Philosophy

### Separation of Powers (Critical)

**BUILD mode CAN:**
- Create new issues (discovered work)
- Add dependencies (found new blocker)
- Update status (open → in_progress → closed)
- Add notes and update descriptions
- Close issues (with verified acceptance criteria)

**BUILD mode CANNOT:**
- Remove dependencies
- Change priority
- Delete issues
- Modify acceptance criteria
- Change issue type

This separation prevents the build agent from "gaming" its way out of difficult work by removing blockers.

### Test-First Acceptance Criteria

All acceptance criteria should be verifiable via commands:
```bash
# Good - specific, automatable
- [ ] Tests pass: `npm test src/auth.test.ts`
- [ ] Lint clean: `npm run lint -- src/auth/`
- [ ] Build succeeds: `npm run build`

# Bad - vague, subjective
- [ ] Code is clean
- [ ] Works correctly
```

## Project Structure

```
how-to-ralph-w-beads/
├── README.md                    # Overview + philosophy
├── QUICKSTART.md               # 5-minute setup guide
├── CLAUDE.md                   # This file
├── AGENTS.md                   # Operational guide for agents
├── .beads/                     # Beads database
├── files/
│   ├── loop.sh                 # Enhanced loop script
│   ├── PROMPT_plan.md          # Planning mode (creates beads)
│   ├── PROMPT_build.md         # Building mode (implements from beads)
│   └── examples/               # Example acceptance criteria patterns
├── docs/
│   ├── ACCEPTANCE_CRITERIA.md  # Standards for verifiable AC
│   ├── LOOP_CONTROL.md         # How exit conditions work
│   ├── EPIC_STRUCTURE.md       # How to structure epics/issues
│   └── MIGRATION.md            # Converting existing Ralph projects
└── examples/
    ├── jtbd-to-epic/           # Example: JTBD → Epic conversion
    └── acceptance-patterns/    # Example: AC patterns by type
```

## Build & Development Commands

```bash
# Run the loop (from target project directory)
./loop.sh              # Build mode, unlimited iterations
./loop.sh 20           # Build mode, max 20 iterations
./loop.sh plan         # Plan mode
./loop.sh plan 5       # Plan mode, max 5 iterations

# Beads commands
bd ready               # Find unblocked work
bd ready --json        # JSON output for scripting
bd list --status open  # All open issues
bd show <id>           # Issue details
bd stats               # Project health overview

# Exit condition check (used by loop.sh)
READY_COUNT=$(bd ready --json 2>/dev/null | jq 'length // 0')
[ "$READY_COUNT" -eq 0 ] && echo "Loop complete"
```

## Acceptance Criteria Patterns

### Pattern 1: Test-Backed (Preferred)
```
- [ ] `npm test src/feature.test.ts` passes
- [ ] `npm run e2e -- --grep "feature"` passes
```

### Pattern 2: Command Output
```
- [ ] `curl localhost:3000/health` returns {"status":"ok"}
- [ ] `grep -r "TODO" src/feature/` returns empty
```

### Pattern 3: Existence Checks
```
- [ ] File exists: src/components/Feature.tsx
- [ ] Export exists: `grep "export.*Feature" src/index.ts`
```

### Pattern 4: LLM-as-Judge (for subjective criteria)
```
- [ ] LLM review confirms: "Error messages are user-friendly"
      Criteria: Each message (1) explains what went wrong, (2) suggests action
```

## Issue Tracking

This project uses **bd (beads)** for issue tracking. All work should be tracked through beads issues.

### Creating Issues

```bash
bd create --title="Issue title" --type=task|bug|feature|epic --priority=2
```

Priority levels: 0-4 or P0-P4 (0=critical, 2=medium, 4=backlog). Do NOT use "high"/"medium"/"low".

### Dependencies Between Issues

Use dependencies to express "this issue cannot be completed until another issue is done."

```bash
# Issue A depends on Issue B (B must be done before A can start)
bd dep add <issue-A> <depends-on-B>

# Alternative: Issue B blocks Issue A
bd dep <blocker-B> --blocks <blocked-A>

# View dependency tree
bd dep tree <issue-id>

# List what an issue depends on or blocks
bd dep list <issue-id>
```

**Example workflow:**
```bash
bd create --title="Design API schema" --type=task        # Creates bd-001
bd create --title="Implement API endpoints" --type=task  # Creates bd-002
bd dep add bd-002 bd-001  # Implement depends on Design (Design blocks Implement)
```

### Epics and Child Issues

Epics are containers for related work. Link child issues to epics using `--parent`.

```bash
# Create an epic
bd create --title="User Authentication System" --type=epic --priority=1

# Create child issues under the epic
bd create --title="Implement login endpoint" --type=task --parent=<epic-id>
bd create --title="Implement logout endpoint" --type=task --parent=<epic-id>
bd create --title="Add session management" --type=task --parent=<epic-id>
```

**Check epic status:**
```bash
bd epic status <epic-id>        # Show completion progress
bd epic close-eligible          # Close epics where all children are complete
```

### Issue Description Best Practices

When creating issues, use `--description` for context/approach and `--acceptance` for acceptance criteria:

```bash
bd create --title="Feature X" --type=feature \
  --description="
## Context
Brief background on why this is needed.

## References
- docs/relevant-doc.md
- src/related/module.ts

## Approach
Pseudo-code or implementation notes:
1. Fetch user data from API
2. Transform response to internal format
3. Cache result with 5-minute TTL
" \
  --acceptance="- User can perform action X
- Error states are handled gracefully
- Unit tests cover happy path and edge cases"
```

The `--acceptance` flag creates a dedicated **ACCEPTANCE CRITERIA** section in the issue, separate from the description.

## Planning Mode Output

When using `/plan` or entering plan mode for implementation tasks, the output MUST be a series of well-defined beads issues.

### Plan Output Requirements

1. **Create an epic** for multi-issue work (3+ related tasks)
2. **Each issue must include:**
   - Clear, actionable title
   - Type (task, bug, feature)
   - Priority (0-4)
   - Parent epic ID (if part of an epic)
   - Dependencies on other issues (if applicable)
   - **Description** (`--description`) with:
     - **Context**: Why this work is needed
     - **References**: Relevant files, docs, or external resources
     - **Approach/Pseudo-code**: Implementation strategy (where applicable)
   - **Acceptance Criteria** (`--acceptance`): Concrete, testable conditions for completion

### Plan Output Format

After planning, create issues like this:

```bash
# Create epic for the body of work
bd create --title="<Epic Title>" --type=epic --priority=<N> \
  --description="
## Overview
<High-level description of the work>

## Success Criteria
<What does done look like for this epic?>
"

# Create child tasks with dependencies
bd create --title="<Task 1>" --type=task --priority=<N> --parent=<epic-id> \
  --description="
## Context
<Why this task exists>

## References
- path/to/relevant/file.ts:42
- docs/design-doc.md

## Approach
<Pseudo-code or step-by-step implementation plan>
" \
  --acceptance="- <Criterion 1>
- <Criterion 2>"

# Add dependencies between tasks
bd dep add <task-that-waits> <task-that-blocks>
```

### Example Plan Output

For a request like "Add user profile editing":

```bash
# Epic
bd create --title="User Profile Editing" --type=epic --priority=2 \
  --description="
## Overview
Allow users to edit their profile information including name, email, and avatar.

## Success Criteria
- Users can update all profile fields
- Changes persist correctly
- Proper validation and error handling
"
# Assume epic ID: bd-abc123

# Task 1: API endpoint
bd create --title="Create profile update API endpoint" --type=task --priority=2 \
  --parent=bd-abc123 \
  --description="
## Context
Backend endpoint needed before frontend can be built.

## References
- src/api/routes/user.ts
- docs/api-design.md

## Approach
// PATCH /api/users/:id/profile
// 1. Validate request body (name, email, avatarUrl)
// 2. Check user authorization
// 3. Update database record
// 4. Return updated profile
" \
  --acceptance="- Endpoint accepts PATCH requests with profile fields
- Returns 400 for invalid input
- Returns 403 for unauthorized access
- Returns 200 with updated profile on success"
# Assume task ID: bd-task1

# Task 2: Frontend form (depends on API)
bd create --title="Build profile edit form component" --type=task --priority=2 \
  --parent=bd-abc123 \
  --description="
## Context
Frontend form for users to edit their profile.

## References
- src/components/Profile/ProfileView.tsx
- src/hooks/useUser.ts

## Approach
1. Create ProfileEditForm component
2. Add form fields for name, email, avatar upload
3. Implement validation (client-side)
4. Call API on submit, handle loading/error states
" \
  --acceptance="- Form displays current profile values
- Client-side validation for email format
- Loading state during submission
- Error messages displayed on failure
- Success feedback and redirect on completion"
# Assume task ID: bd-task2

# Set dependency: frontend depends on API
bd dep add bd-task2 bd-task1
```

For more workflow details: `bd prime`
