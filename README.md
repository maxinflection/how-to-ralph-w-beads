# how-to-ralph-w-beads

**Agentic coding loops with deterministic exit conditions.**

A fork of [ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook) that replaces markdown-based planning with [beads](https://github.com/steveyegge/beads) structured issue tracking.

## The Problem

Ralph's power comes from persistent iteration - but that persistence can become infinite loops:
- Vague acceptance criteria ("works correctly") can never be verified
- No dependency tracking means agents retry impossible work
- No separation between planning and building lets agents "game" their way out of hard tasks

## The Solution

Replace `IMPLEMENTATION_PLAN.md` with a beads dependency graph:

| Ralph Original | Beads Replacement |
|----------------|-------------------|
| `IMPLEMENTATION_PLAN.md` | `bd ready` queue + dependency graph |
| `specs/*.md` | Beads epics with child issues |
| "Task" in markdown plan | Beads issue (task/feature/bug) |
| "Topic of Concern" | Beads epic |
| Gap analysis output | `bd list --status open` |
| "Most important task" | `bd ready --limit 1` |

## Key Innovations

### 1. Verifiable Exit Conditions

The loop exits when `bd ready` returns empty:
```bash
READY_COUNT=$(bd ready --json | jq 'length')
[ "$READY_COUNT" -eq 0 ] && echo "Done!"
```

### 2. Test-First Acceptance Criteria

Every issue has machine-verifiable acceptance criteria:
```
- [ ] Login returns JWT | `npm test auth.test.ts` | exit 0
- [ ] No lint errors | `npm run lint` | exit 0
```

### 3. Separation of Powers

BUILD mode can implement and close issues but CANNOT:
- Remove dependencies (would let it skip hard work)
- Change priorities (would let it deprioritize hard work)
- Modify acceptance criteria (would let it lower the bar)

Only PLANNING mode can make structural changes.

### 4. Stuck Detection

After 3 failed attempts on the same issue, the loop moves on and flags it for planning review.

## Quick Start

Two workflows are supported:

### Workflow 1: Specs-First (Traditional Ralph)

```bash
# Copy files to your project
cp -r files/* your-project/
cd your-project

# Initialize beads
bd init

# Create specs/*.md files defining requirements

# Run planning (creates issues from specs)
./loop.sh plan

# Run building (implements from issue queue)
./loop.sh build
```

### Workflow 2: Beads-First (No Specs Required)

```bash
# Copy files to your project
cp -r files/* your-project/
cd your-project

# Initialize beads
bd init

# Create epics and issues directly (e.g., in Claude Code)
bd create --title="Epic: User Auth" --type=epic --priority=1 \
  --description="Implement user authentication system"
bd create --title="Add login endpoint" --type=task --priority=1 \
  --parent=<epic-id> \
  --acceptance="- [ ] Login test passes | \`npm test auth\` | exit 0"

# Skip planning, go straight to building
./loop.sh build
```

The beads-first workflow is useful when you:
- Already have a clear mental model of the work
- Want to define issues interactively in Claude Code
- Don't need the gap analysis that planning provides

See [QUICKSTART.md](QUICKSTART.md) for the full 5-minute setup guide.

## Project Structure

```
files/
├── loop.sh              # Enhanced loop with beads integration
├── PROMPT_plan.md       # Planning mode prompt
├── PROMPT_build.md      # Building mode prompt
└── AGENTS.md            # Template for target projects

docs/
├── ACCEPTANCE_CRITERIA.md  # AC format and patterns
├── LOOP_CONTROL.md         # Exit condition documentation
└── MIGRATION.md            # Converting existing Ralph projects
```

## How It Works

### Planning Mode

```bash
./loop.sh plan
```

1. Studies specs and existing code
2. Triages stuck and blocked issues
3. Creates new issues with verifiable acceptance criteria
4. Wires up dependencies
5. Does NOT implement anything

### Building Mode

```bash
./loop.sh build
```

1. Picks highest-priority ready task (`bd ready`)
2. Creates test scaffolding (before implementation)
3. Implements functionality
4. Verifies ALL acceptance criteria
5. Closes with evidence and commits
6. Loops until `bd ready` is empty

### Output Logging (RALPH_LOG)

Enable logging to capture all loop output for debugging and analysis:

```bash
# Enable logging via CLI flag
./loop.sh --log build
./loop.sh --log plan 5

# Or via environment variable
RALPH_LOG=1 ./loop.sh build

# Logs are written to: ~/.local/state/ralph/projects/<hash>/logs/
# Each run creates a timestamped log file (e.g., 2026-01-28T15-30-00.log)
```

Logs contain interleaved JSONL with loop metadata and claude output:
```jsonl
{"type":"loop_meta","event":"iteration_start","timestamp":"...","data":{"iteration":1,"issue_id":"bd-abc"}}
{"type":"claude_output",...}
{"type":"loop_meta","event":"iteration_end","timestamp":"...","data":{"iteration":1,"exit_code":0,"duration_seconds":45}}
```

### External State Directory

Ralph stores all state files outside your project directory to remain "invisible":

```
~/.local/state/ralph/
  projects/
    <project-hash>/        # SHA256(git-remote-url)[:12]
      attempts.txt         # Attempt tracking (persistent across sessions)
      metadata.json        # Project name, path, remote URL
      logs/                # Output logs (when RALPH_LOG=1)
```

Override the location with `RALPH_STATE_DIR`:
```bash
RALPH_STATE_DIR=/tmp/ralph ./loop.sh build
```

### Scoped Loops (RALPH_SCOPE)

Run loops scoped to a specific epic, useful for feature branches or worktrees:

```bash
# Only work on issues within epic htrwb-abc
RALPH_SCOPE=htrwb-abc ./loop.sh build

# Scoped planning
RALPH_SCOPE=htrwb-abc ./loop.sh plan 5
```

When `RALPH_SCOPE` is set:
- `bd ready` filters to children of that epic
- Loop exits when scoped work is complete (not global work)
- Prompts inform the agent of scope restrictions
- New issues should be created under the scoped epic

**Worktree workflow:**
```bash
# Create worktree for feature
git worktree add ../my-feature feature/my-feature
cd ../my-feature

# Create epic for this feature
bd create --title="Epic: My Feature" --type=epic --priority=1
# Returns: htrwb-xyz

# Run scoped loop
RALPH_SCOPE=htrwb-xyz ./loop.sh build
```

This enables parallel development: different worktrees work on different epics simultaneously without interference.

## Comparison with Original Ralph

| Aspect | Original Ralph | Ralph + Beads |
|--------|---------------|---------------|
| Plan format | Markdown | Structured JSON (beads) |
| Dependencies | Implicit in text | Explicit graph edges |
| Ready work | Parse markdown | `bd ready` query |
| Exit condition | Manual/iteration limit | Empty queue + AC verified |
| Acceptance | Informal | Mandatory, verifiable |
| Stuck detection | Manual | Automatic (3 attempts) |
| Structural changes | Anytime | PLANNING mode only |

## Documentation

- [QUICKSTART.md](QUICKSTART.md) - 5-minute setup
- [CLAUDE.md](CLAUDE.md) - Full project guidance
- [docs/ACCEPTANCE_CRITERIA.md](docs/ACCEPTANCE_CRITERIA.md) - AC patterns
- [docs/LOOP_CONTROL.md](docs/LOOP_CONTROL.md) - Exit conditions

## Credits

- Original Ralph concept by [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Ralph Playbook by [Clayton Farr](https://github.com/ClaytonFarr/ralph-playbook)
- Beads by [Steve Yegge](https://github.com/steveyegge/beads)
