# Loop Control: Preventing Infinite Iterations

## The Ralph Challenge

Ralph's power comes from persistence - but unchecked persistence wastes resources and can loop forever on impossible tasks. Beads provides deterministic exit conditions that let the loop terminate reliably.

## Exit Condition 1: Empty Ready Queue

The primary exit condition in BUILD mode:

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

**Why this works**: The beads dependency graph ensures that work can only proceed when its blockers are resolved. When nothing is ready, either everything is done or there's a dependency cycle that requires human intervention.

## Exit Condition 2: Acceptance Criteria Satisfaction

Each task's acceptance criteria form a checklist. The agent MUST verify each before calling `bd close`. This prevents "false done" states where work appears complete but doesn't meet requirements.

```bash
# In PROMPT_build.md, Phase 5:
# "Only close when ALL acceptance criteria are met"

bd close <id> --reason "
Acceptance criteria verified:
- [x] Unit tests pass (npm test auth.test.ts - exit 0)
- [x] Integration test passes (npm run e2e login - exit 0)
- [x] TypeScript compiles (tsc --noEmit - exit 0)
"
```

The close reason creates an audit trail showing HOW each criterion was verified.

## Exit Condition 3: Max Iterations (Safety Valve)

A hard limit prevents runaway loops:

```bash
./loop.sh build 50  # Maximum 50 iterations
```

When max iterations hit:
1. Loop stops gracefully
2. Current work state preserved in beads
3. Human reviews `bd list --status in_progress` for stuck work
4. Human reviews `bd blocked` for dependency issues

## State Directory

Ralph stores all operational state outside the project directory to remain "invisible" to your codebase. This means `git status` stays clean - no `.ralph-*` files appear in your project.

### Location

```
~/.local/state/ralph/
  projects/
    <project-hash>/        # SHA256(git-remote-url)[:12]
      attempts.txt         # Attempt tracking per issue
      metadata.json        # Project identification
      logs/                # Output logs (when RALPH_LOG=1)
```

The project hash is derived from your git remote URL, so the same repository cloned to different locations will share the same state directory.

### Overriding

```bash
# Use a custom state directory
RALPH_STATE_DIR=/tmp/my-ralph-state ./loop.sh build
```

### Legacy Migration

If you have an existing `.ralph-attempts` file in your project directory, Ralph will warn you:
```
[WARN] Legacy .ralph-attempts file found in project directory
       Ralph now stores state externally at: ~/.local/state/ralph/projects/abc123def456
       You can safely delete .ralph-attempts
```

## Stuck Detection

If the same issue stays `in_progress` for multiple iterations without completing, it's likely stuck. The loop tracks attempts per issue:

```bash
# Attempts are stored externally at:
# ~/.local/state/ralph/projects/<hash>/attempts.txt
MAX_STUCK_ATTEMPTS=3

# After 3 failed attempts on the same issue:
bd update <id> --notes "STUCK: Failed after 3 attempts at $(date). Moving to next issue."
```

The PLANNING mode will later review stuck issues and decide whether to:
- Adjust priority
- Add/remove dependencies
- Split into smaller issues
- Mark as blocked pending external input

### What Constitutes a "Failed Attempt"?

An attempt "fails" when:
1. The iteration completes but the issue isn't closed
2. The acceptance criteria weren't all verified
3. The agent moved on without closing the issue

The loop increments the counter at the start of each iteration. If the issue is closed during that iteration, the counter resets.

## Preventing Circumvention

The acceptance criteria model prevents gaming because:

### 1. Criteria are Written During PLANNING

Acceptance criteria are defined before implementation begins. The BUILD agent cannot modify them - it can only verify them.

### 2. Criteria Reference Specific Commands

Verification is objective: run the command, check the exit code. No subjective judgment about whether something "looks done."

### 3. Close Reasons Must Cite Evidence

The `--reason` flag isn't optional. It must include specific verification results, creating an audit trail.

### 4. Beads Tracks All Changes

Every status change, note addition, and close reason is recorded. Suspicious patterns (closing without verification) are visible in the audit log.

## Separation of Powers (Critical)

The key to preventing infinite loops is separating WHO can do WHAT:

### BUILD Mode CAN:
- Create new issues (discovered work)
- Add dependencies (found new blocker)
- Update status (open → in_progress → closed)
- Add notes and update descriptions
- Close issues (with verified acceptance criteria)

### BUILD Mode CANNOT:
- Remove dependencies
- Change priority
- Delete issues
- Modify acceptance criteria
- Change issue type

### Only PLANNING Mode CAN:
- Remove dependencies (after analysis)
- Adjust priorities (based on new information)
- Modify acceptance criteria (refine scope)
- Delete/archive issues (obsolete work)
- Restructure epic/task relationships

**Why this matters**: A BUILD agent that's stuck on a difficult task cannot "game" its way out by:
- Removing the blocker dependency (CANNOT)
- Lowering the priority so something else gets picked (CANNOT)
- Changing the acceptance criteria to be easier (CANNOT)
- Deleting the issue entirely (CANNOT)

Instead, it must either:
1. Actually complete the work to spec
2. Add notes explaining why it's stuck and move on
3. Create a blocking issue for the discovered problem

The PLANNING loop then reviews the situation with fresh context and makes structural decisions.

## Output Logging

Enable logging to capture all loop output for debugging:

```bash
RALPH_LOG=1 ./loop.sh build
```

Logs are written to `~/.local/state/ralph/projects/<hash>/logs/` with timestamped filenames.

### Log Format

Logs use interleaved JSONL format:
```jsonl
{"type":"loop_meta","event":"iteration_start","timestamp":"2026-01-28T15:30:00Z","data":{"iteration":1,"issue_id":"bd-abc","mode":"build"}}
... claude stream-json output ...
{"type":"loop_meta","event":"iteration_end","timestamp":"2026-01-28T15:30:45Z","data":{"iteration":1,"exit_code":0,"duration_seconds":45}}
```

This allows post-hoc analysis:
```bash
# Extract just metadata events
grep '"type":"loop_meta"' ~/.local/state/ralph/projects/*/logs/*.log | jq

# Calculate total iteration time
jq -s '[.[] | select(.event=="iteration_end") | .data.duration_seconds] | add' < log.log

# Find failed iterations
jq 'select(.event=="iteration_end" and .data.exit_code != 0)' < log.log
```

### Log Retention

By default, the 10 most recent log files are retained. Override with:
```bash
RALPH_LOG_RETENTION=20 RALPH_LOG=1 ./loop.sh build
```

## Troubleshooting Runaway Loops

### Symptom: Loop keeps running but nothing closes

**Check**: Are acceptance criteria verifiable?
```bash
bd list --status in_progress --json | jq '.[].acceptance'
```
If criteria are vague ("works correctly"), the agent can't verify them. Fix in PLANNING mode.

### Symptom: Same issue picked repeatedly

**Check**: Is stuck detection working?
```bash
# Attempts file is stored externally
cat ~/.local/state/ralph/projects/*/attempts.txt
# Or check the specific project's state directory shown in loop header
```
If an issue has 3+ attempts, the loop should skip it. Check loop.sh implementation.

### Symptom: Loop exits immediately

**Check**: Is there ready work?
```bash
bd ready
bd blocked
```
If everything is blocked, you have a dependency problem. Review in PLANNING mode.

### Symptom: Issues closed without real completion

**Check**: Close reasons
```bash
bd show <id> --json | jq '.close_reason'
```
If reasons are missing or vague, the PROMPT_build.md guardrails may not be strong enough.

## Recovery Procedures

### Reset a Stuck Issue
```bash
bd update <id> --status open --notes "Reset for retry"
# Clear attempt counter (state directory shown in loop header)
rm ~/.local/state/ralph/projects/<hash>/attempts.txt
```

### Force a Full Replan
```bash
# Close all in_progress issues as incomplete
bd list --status in_progress --json | jq -r '.[].id' | \
  xargs -I{} bd update {} --status open --notes "Reset for replanning"

# Run planning mode
./loop.sh plan
```

### Abort and Review
```bash
# Ctrl+C to stop the loop

# Review current state
bd stats
bd list --status in_progress
bd blocked

# Manually triage before restarting
```
