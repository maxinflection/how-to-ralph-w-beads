# Migrating Existing Ralph Projects to Beads

This guide covers converting projects using the original [ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook) to the beads-integrated version.

## Prerequisites

1. Install beads: `npm install -g @beads/bd` or `brew install beads`
2. Backup your current `IMPLEMENTATION_PLAN.md`
3. Have the ralph-beads files ready to copy

## Migration Steps

### 1. Initialize Beads

```bash
cd your-project
bd init
```

### 2. Copy New Files

```bash
# From ralph-beads repo
cp files/loop.sh your-project/
cp files/PROMPT_plan.md your-project/
cp files/PROMPT_build.md your-project/
cp files/AGENTS.md your-project/  # Review and merge with existing

chmod +x your-project/loop.sh
```

### 3. Convert IMPLEMENTATION_PLAN.md to Beads Issues

#### Manual Conversion

For each item in your markdown plan:

```markdown
# Original IMPLEMENTATION_PLAN.md
- [ ] P1: Implement user auth
  - [ ] Add login endpoint
  - [ ] Add logout endpoint
- [ ] P2: Add dashboard
```

Becomes:

```bash
# Create epic
bd create --title="User Authentication" --type=epic --priority=1
# Returns: bd-a1b2

# Create child tasks
bd create --title="Add login endpoint" --type=task --priority=1 \
  --parent=bd-a1b2 \
  --acceptance="- [ ] POST /auth/login returns JWT | \`npm test auth.test.ts\` | exit 0
- [ ] Invalid creds return 401 | \`npm test auth.test.ts --grep 401\` | exit 0"

bd create --title="Add logout endpoint" --type=task --priority=1 \
  --parent=bd-a1b2 \
  --acceptance="- [ ] POST /auth/logout invalidates session | \`npm test auth.test.ts\` | exit 0"

# Wire dependency (logout depends on login existing)
bd dep add bd-a1b2.2 bd-a1b2.1
```

#### Automated Conversion Script

For simple plans, use this script as a starting point:

```bash
#!/bin/bash
# migrate-plan.sh - Convert IMPLEMENTATION_PLAN.md to beads
# Customize the parsing for your specific plan format

grep -E "^- \[ \]" IMPLEMENTATION_PLAN.md | while read -r line; do
    # Extract priority (P0, P1, P2, etc)
    PRIORITY=$(echo "$line" | grep -oE "P[0-4]" | sed 's/P//')
    PRIORITY=${PRIORITY:-2}  # Default P2

    # Extract title (remove checkbox and priority prefix)
    TITLE=$(echo "$line" | sed 's/^- \[ \] //' | sed 's/P[0-4]: //')

    # Create issue (you'll need to add acceptance criteria manually)
    bd create --title="$TITLE" --type=task --priority="$PRIORITY" \
      --acceptance="- [ ] TODO: Add verification | \`true\` | exit 0"

    echo "Created: $TITLE"
done
```

### 4. Convert specs/*.md to Epics

Each spec file can become an epic:

```bash
# Read spec content
SPEC_CONTENT=$(cat specs/auth.md)

# Create epic with spec as description
bd create --title="Auth System" --type=epic --priority=1 \
  --description="$SPEC_CONTENT"
```

Then create child tasks for each major section of the spec.

### 5. Run Planning Mode

Let the beads-integrated planning mode analyze and fill gaps:

```bash
./loop.sh plan 3
```

This will:
- Read your specs
- Compare against existing code
- Create any missing issues
- Set up dependencies

### 6. Archive Old Files

Once migration is verified:

```bash
# Archive old files (don't delete yet)
mkdir -p archive
mv IMPLEMENTATION_PLAN.md archive/
# Keep specs/ - they're still used as reference
```

## Gotchas and Edge Cases

### Nested Items

Original Ralph supports arbitrary nesting. Beads uses flat issues with dependencies:

```markdown
# Original (nested)
- [ ] Auth
  - [ ] Login
    - [ ] JWT generation
    - [ ] Session storage
```

```bash
# Beads (flat with deps)
bd create --title="Auth" --type=epic --priority=1       # bd-a1
bd create --title="Login" --type=task --parent=bd-a1    # bd-a1.1
bd create --title="JWT generation" --type=task --parent=bd-a1  # bd-a1.2
bd create --title="Session storage" --type=task --parent=bd-a1 # bd-a1.3

# Wire dependencies
bd dep add bd-a1.1 bd-a1.2  # Login depends on JWT
bd dep add bd-a1.1 bd-a1.3  # Login depends on Session
```

### Completed Items

Items marked as done in markdown can be imported as closed:

```bash
bd create --title="Already done task" --type=task --priority=2
TASK_ID=$(bd list --json | jq -r '.[-1].id')
bd close "$TASK_ID" --reason "Migrated from IMPLEMENTATION_PLAN.md - was already complete"
```

### Acceptance Criteria Backfill

Old plans often lack verifiable acceptance criteria. During migration:

1. Add minimal criteria: `- [ ] Implementation exists | \`test -f src/feature.ts\` | exit 0`
2. Run planning mode to refine them
3. Or leave as `MANUAL` for human verification

### In-Progress Work

If you have active work when migrating:

```bash
# Create the issue
bd create --title="Current work" --type=task --priority=1 \
  --acceptance="..."

# Mark as in_progress
TASK_ID=$(bd list --json | jq -r '.[-1].id')
bd update "$TASK_ID" --status in_progress --notes "Migrated from active work in IMPLEMENTATION_PLAN.md"
```

## Verification

After migration, verify:

```bash
# Check issue count matches plan items
bd stats

# Check ready queue makes sense
bd ready

# Check for orphan issues (no parent or deps)
bd list --json | jq '.[] | select(.parent == null and .blockedBy == [])'

# Run planning mode to find gaps
./loop.sh plan 1
```

## Rollback

If migration fails:

```bash
# Restore old files
mv archive/IMPLEMENTATION_PLAN.md .

# Remove beads
rm -rf .beads

# Use old loop.sh (if you saved it)
```
