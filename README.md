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

```bash
# Copy files to your project
cp -r files/* your-project/
cd your-project

# Initialize beads
bd init

# Run planning (creates issues from specs)
./loop.sh plan

# Run building (implements from issue queue)
./loop.sh build
```

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
