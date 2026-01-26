# AGENTS.md - Project Operational Guide

## Issue Tracking with Beads

This project uses `bd` (beads) for issue tracking. ALL work flows through beads.

### Starting a Session

```bash
bd ready                        # What's available to work on
bd list --status in_progress    # What's already claimed

TASK=$(bd ready --json | jq -r '.[0].id')
bd show $TASK                   # Read full context
bd update $TASK --status in_progress  # Claim it
```

### During Implementation

```bash
# Discovered new work? File it immediately
bd create --title="Found: [issue]" --type=bug --priority=2 \
  --description="Discovered while working on $TASK"

# Learning something? Capture it
bd update $TASK --notes "Insight: [what you learned]"
```

### Completing Work

```bash
# ONLY when all acceptance criteria verified:
bd show $TASK  # Review criteria one more time

bd close $TASK --reason "
Verified:
- [x] [criterion 1] - [how verified]
- [x] [criterion 2] - [how verified]
"

git add -A && git commit -m "[$TASK] [description]"
```

### Ending a Session

```bash
bd sync        # Sync with git
git push       # Push all changes
```

## Build Mode Restrictions

During BUILD mode, you CANNOT:
- Remove dependencies (requires PLANNING mode)
- Change priorities (requires PLANNING mode)
- Modify acceptance criteria (requires PLANNING mode)
- Delete issues (requires PLANNING mode)

If stuck, add notes and move to next ready task.

## Build & Test Commands

[Project-specific commands - customize this section]

```bash
# Install dependencies
[your install command]

# Build
[your build command]

# Test
[your test command]

# Lint
[your lint command]

# Typecheck (if applicable)
[your typecheck command]
```

## Operational Notes

[Add learnings about how to run/debug the project here]
