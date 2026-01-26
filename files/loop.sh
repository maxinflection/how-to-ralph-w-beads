#!/bin/bash
# Ralph+Beads Loop - Agentic coding loop with beads issue tracking
#
# Usage: ./loop.sh [plan|build] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh plan         # Plan mode, unlimited iterations
#   ./loop.sh plan 5       # Plan mode, max 5 iterations
#
# Exit conditions:
#   1. bd ready returns empty (no unblocked work) - BUILD mode only
#   2. Max iterations reached
#   3. Ctrl+C (manual stop)
#
# Stuck detection:
#   After 3 failed attempts on the same issue, the agent adds notes
#   and moves to the next ready task.

set -euo pipefail

# Configuration
ATTEMPT_FILE=".ralph-attempts"
MAX_STUCK_ATTEMPTS=3
PROMPT_DIR="${PROMPT_DIR:-files}"

# Parse arguments
if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    MODE="build"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_build.md"
    MAX_ITERATIONS=${1:-0}
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure beads is initialized
if [ ! -d ".beads" ]; then
    log_info "Initializing beads..."
    bd init --quiet
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode:   $MODE"
echo "Prompt: $PROMPT_FILE"
echo "Branch: $CURRENT_BRANCH"
[ "$MAX_ITERATIONS" -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    log_error "$PROMPT_FILE not found"
    exit 1
fi

# Function to get current ready issue ID
get_ready_issue() {
    bd ready --json 2>/dev/null | jq -r '.[0].id // empty'
}

# Function to get attempt count for an issue
get_attempts() {
    local issue_id="$1"
    grep "^${issue_id}:" "$ATTEMPT_FILE" 2>/dev/null | cut -d: -f2 || echo 0
}

# Function to increment attempt count
increment_attempts() {
    local issue_id="$1"
    local current_attempts
    current_attempts=$(get_attempts "$issue_id")
    local new_attempts=$((current_attempts + 1))

    # Remove old entry and add new one
    grep -v "^${issue_id}:" "$ATTEMPT_FILE" > "${ATTEMPT_FILE}.tmp" 2>/dev/null || true
    echo "${issue_id}:${new_attempts}" >> "${ATTEMPT_FILE}.tmp"
    mv "${ATTEMPT_FILE}.tmp" "$ATTEMPT_FILE"

    echo "$new_attempts"
}

# Function to reset attempts for an issue
reset_attempts() {
    local issue_id="$1"
    grep -v "^${issue_id}:" "$ATTEMPT_FILE" > "${ATTEMPT_FILE}.tmp" 2>/dev/null || true
    mv "${ATTEMPT_FILE}.tmp" "$ATTEMPT_FILE" 2>/dev/null || touch "$ATTEMPT_FILE"
}

# Function to check if issue is stuck
check_stuck() {
    local issue_id="$1"
    local attempts
    attempts=$(get_attempts "$issue_id")

    if [ "$attempts" -ge "$MAX_STUCK_ATTEMPTS" ]; then
        log_warn "Issue $issue_id stuck after $attempts attempts"

        # Add notes about being stuck
        bd update "$issue_id" --notes "STUCK: Failed after $attempts attempts at $(date). Moving to next issue." 2>/dev/null || true

        # Reset attempts (will try again later if it becomes ready)
        reset_attempts "$issue_id"

        return 0  # Is stuck
    fi

    return 1  # Not stuck
}

# Initialize attempt file
touch "$ATTEMPT_FILE"

# Main loop
while true; do
    # Exit condition 1: Max iterations reached
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
        log_success "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Exit condition 2: No ready work (BUILD mode only)
    if [ "$MODE" = "build" ]; then
        READY_COUNT=$(bd ready --json 2>/dev/null | jq 'length // 0')

        if [ "$READY_COUNT" -eq 0 ]; then
            log_success "No ready work remaining - loop complete!"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "All unblocked work has been completed."
            echo "Run 'bd list --status open' to see remaining blocked work."
            echo "Run 'bd blocked' to see what's blocking them."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            break
        fi

        # Get current issue and check if stuck
        CURRENT_ISSUE=$(get_ready_issue)
        if [ -n "$CURRENT_ISSUE" ]; then
            if check_stuck "$CURRENT_ISSUE"; then
                log_warn "Skipping stuck issue, trying next..."
                # Loop will pick up next ready issue on next iteration
                sleep 1
                continue
            fi

            # Increment attempts for this issue
            ATTEMPTS=$(increment_attempts "$CURRENT_ISSUE")
            log_info "Working on $CURRENT_ISSUE (attempt $ATTEMPTS/$MAX_STUCK_ATTEMPTS)"
        fi
    fi

    # Show iteration header
    ITERATION=$((ITERATION + 1))
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                     ITERATION $ITERATION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Show current state
    if [ "$MODE" = "build" ]; then
        log_info "Ready queue:"
        bd ready 2>/dev/null | head -5 || true
        echo ""
    fi

    # Run Ralph iteration with selected prompt
    # -p: Headless mode (non-interactive, reads from stdin)
    # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
    # --output-format=stream-json: Structured output for logging/monitoring
    # --model opus: Primary agent uses Opus for complex reasoning
    # --verbose: Detailed execution logging

    LAST_EXIT=0
    cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose || LAST_EXIT=$?

    # Check if iteration was successful
    if [ "$LAST_EXIT" -ne 0 ]; then
        log_warn "Iteration ended with exit code $LAST_EXIT"
    else
        # Reset attempts on success (issue was likely closed)
        if [ -n "${CURRENT_ISSUE:-}" ]; then
            # Check if issue was closed
            ISSUE_STATUS=$(bd show "$CURRENT_ISSUE" --json 2>/dev/null | jq -r '.status // "unknown"')
            if [ "$ISSUE_STATUS" = "closed" ]; then
                log_success "Issue $CURRENT_ISSUE closed successfully"
                reset_attempts "$CURRENT_ISSUE"
            fi
        fi
    fi

    # Sync beads and push changes
    log_info "Syncing changes..."
    bd sync 2>/dev/null || log_warn "bd sync had warnings"

    git push origin "$CURRENT_BRANCH" 2>/dev/null || {
        log_info "Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH" || log_warn "Push failed"
    }

    echo ""
done

# Final summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Loop finished after $ITERATION iterations"
echo ""
bd stats 2>/dev/null || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup
rm -f "$ATTEMPT_FILE" 2>/dev/null || true
