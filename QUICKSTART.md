# Ralph+Beads Quickstart

Get up and running in 5 minutes.

## Prerequisites

1. **beads** installed: `npm install -g @beads/bd` or `brew install beads`
2. **claude** CLI installed with API access
3. A project with specs in `specs/*.md`

## Setup

### 1. Copy the Files

```bash
# From ralph-beads repo
cp -r files/* your-project/
chmod +x your-project/loop.sh
```

### 2. Initialize Beads

```bash
cd your-project
bd init
```

### 3. Customize AGENTS.md

Edit `AGENTS.md` to add your project's build/test commands:

```bash
# Replace placeholders with your actual commands
vim AGENTS.md
```

## First Planning Loop

Create your initial work queue:

```bash
# Run planning mode (analyzes specs, creates issues)
./loop.sh plan 3
```

This will:
1. Read your `specs/*.md` files
2. Compare against existing code
3. Create beads issues with acceptance criteria
4. Set up dependencies

Check the results:

```bash
bd stats        # Overview
bd ready        # What's available to work on
bd list         # All issues
```

## First Build Loop

Start implementing:

```bash
# Run build mode (implements from ready queue)
./loop.sh build 5
```

This will:
1. Pick the highest-priority ready task
2. Create test scaffolding
3. Implement the functionality
4. Verify acceptance criteria
5. Close the issue and commit
6. Loop until done or max iterations

Watch the output. The loop will:
- Exit when `bd ready` is empty (all work done)
- Skip stuck issues after 3 attempts
- Push to git after each iteration

## Verify Exit Conditions Work

After a few iterations, check:

```bash
# Should show decreasing ready count
bd ready

# Should show some closed issues
bd list --status closed

# Check for stuck issues
cat .ralph-attempts
```

## Common Operations

### See What's Ready
```bash
bd ready
```

### Create a New Issue Manually
```bash
bd create --title="Fix login bug" --type=bug --priority=1 \
  --acceptance="- [ ] Login test passes | \`npm test auth\` | exit 0"
```

### Check Blocked Work
```bash
bd blocked
```

### Run Unlimited Build
```bash
./loop.sh  # Runs until bd ready is empty
```

### Run Planning to Rebalance
```bash
./loop.sh plan  # Triage stuck work, create new issues
```

## Troubleshooting

### Loop Exits Immediately
```bash
bd ready  # Check if there's work
bd blocked  # Check if everything is blocked
```

### Same Issue Picked Repeatedly
```bash
cat .ralph-attempts  # Check attempt counts
rm .ralph-attempts   # Reset if needed
```

### Need to Replan
```bash
./loop.sh plan 5  # Run planning mode to restructure
```

## Next Steps

- Read [ACCEPTANCE_CRITERIA.md](docs/ACCEPTANCE_CRITERIA.md) for AC patterns
- Read [LOOP_CONTROL.md](docs/LOOP_CONTROL.md) for exit condition details
- Read [CLAUDE.md](CLAUDE.md) for full project documentation
