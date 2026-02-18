#!/bin/bash
# Ralph+Beads Loop - Agentic coding loop with beads issue tracking
#
# Usage: ./loop.sh [--log] [plan|build] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh build        # Build mode, unlimited iterations (explicit)
#   ./loop.sh build 10     # Build mode, max 10 iterations
#   ./loop.sh plan         # Plan mode, unlimited iterations
#   ./loop.sh plan 5       # Plan mode, max 5 iterations
#   ./loop.sh --log build  # Build mode with logging enabled
#   ./loop.sh --log plan 5 # Plan mode with logging, max 5 iterations
#
# Environment variables:
#   RALPH_LOG=1            Enable output logging to external state directory
#   RALPH_STATE_DIR=<path> Override state directory (default: ~/.local/state/ralph)
#   RALPH_SCOPE=<epic-id>  Filter to children of a specific epic
#   PROMPT_DIR=<path>      Override prompt files directory (default: same dir as loop.sh)
#
# Exit conditions:
#   1. bd ready returns empty (no unblocked work) - BUILD mode only
#   2. Max iterations reached
#   3. Ctrl+C (manual stop)
#
# Stuck detection:
#   After 3 failed attempts on the same issue, the agent adds notes
#   and moves to the next ready task.
#
# State management:
#   All state files (attempts, logs) are stored externally in:
#   ~/.local/state/ralph/projects/<project-hash>/
#   This keeps the target project directory clean.

set -euo pipefail

# Get script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source state management library
source "${SCRIPT_DIR}/ralph-state.sh"

# Initialize external state directory
init_ralph_state

# Cleanup temp files on exit
cleanup() { rm -f "${_ITER_OUTPUT_FILE:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Configuration
ATTEMPT_FILE=$(get_attempts_file)
MAX_STUCK_ATTEMPTS=3
PROMPT_DIR="${PROMPT_DIR:-$SCRIPT_DIR}"  # Prompts live alongside this script
RALPH_SCOPE="${RALPH_SCOPE:-}"  # Optional: filter to epic children
CCUSAGE_CMD="${CCUSAGE_CMD:-npx ccusage}"  # Override with e.g. "bunx ccusage" or direct path
_ITER_OUTPUT_FILE=""

# Ensure a value is a non-negative integer, default to 0
# Usage: MAX_ITERATIONS=$(ensure_int "$value")
ensure_int() {
    local val="${1:-0}"
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val"
    else
        echo "0"
    fi
}

# Parse arguments
# Support: ./loop.sh [--log] [plan|build] [max_iterations]
if [ "${1:-}" = "--log" ]; then
    export RALPH_LOG=1
    shift
fi

if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_plan.md"
    MAX_ITERATIONS=$(ensure_int "${2:-0}")
elif [ "${1:-}" = "build" ]; then
    MODE="build"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_build.md"
    MAX_ITERATIONS=$(ensure_int "${2:-0}")
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_build.md"
    MAX_ITERATIONS=$(ensure_int "$1")
else
    MODE="build"
    PROMPT_FILE="${PROMPT_DIR}/PROMPT_build.md"
    MAX_ITERATIONS=0
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
[ -n "$RALPH_SCOPE" ] && echo "Scope:  $RALPH_SCOPE (epic-scoped)"
[ "$MAX_ITERATIONS" -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
get_ralph_state_info
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    log_error "$PROMPT_FILE not found"
    exit 1
fi

# Build bd ready command with optional scope filter
get_bd_ready_cmd() {
    if [ -n "$RALPH_SCOPE" ]; then
        echo "bd ready --parent=${RALPH_SCOPE} --json"
    else
        echo "bd ready --json"
    fi
}

# Function to get current ready issue ID
get_ready_issue() {
    $(get_bd_ready_cmd) 2>/dev/null | jq -r '.[0].id // empty'
}

# Function to get attempt count for an issue
get_attempts() {
    local issue_id="$1"
    local val
    val=$(grep "^${issue_id}:" "$ATTEMPT_FILE" 2>/dev/null | cut -d: -f2 || echo 0)
    ensure_int "$val"
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

# Function to decrement attempt count (undo a pre-iteration increment)
decrement_attempts() {
    local issue_id="$1"
    local current_attempts
    current_attempts=$(get_attempts "$issue_id")
    local new_attempts=$((current_attempts > 0 ? current_attempts - 1 : 0))

    grep -v "^${issue_id}:" "$ATTEMPT_FILE" > "${ATTEMPT_FILE}.tmp" 2>/dev/null || true
    echo "${issue_id}:${new_attempts}" >> "${ATTEMPT_FILE}.tmp"
    mv "${ATTEMPT_FILE}.tmp" "$ATTEMPT_FILE"
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

# Check if iteration output indicates quota exhaustion
# Returns 0 if rate_limit error found in stream-json output
check_quota_exhaustion() {
    local output_file="$1"
    [ -f "$output_file" ] || return 1
    grep -q '"error":"rate_limit"' "$output_file" 2>/dev/null
}

# Calculate seconds until quota resets
# Tries ccusage for exact endTime, falls back to parsing message, ultimate fallback 5h
get_quota_reset_seconds() {
    local message="${1:-}"
    local now_epoch reset_epoch sleep_secs

    now_epoch=$(date +%s)

    # Try ccusage for exact block end time
    if command -v npx &>/dev/null || command -v bunx &>/dev/null; then
        local end_time
        end_time=$($CCUSAGE_CMD blocks --active --json 2>/dev/null | jq -r '.blocks[0].endTime // empty' 2>/dev/null) || true
        if [ -n "$end_time" ]; then
            reset_epoch=$(date -d "$end_time" +%s 2>/dev/null) || true
            if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
                sleep_secs=$((reset_epoch - now_epoch + 60))  # 60s buffer
                echo "$sleep_secs"
                return
            fi
        fi
    fi

    # Fallback: parse reset hour from error message ("resets 6am (UTC)")
    local reset_hour
    reset_hour=$(echo "$message" | grep -oP 'resets \K[0-9]+' 2>/dev/null) || true
    if [ -n "$reset_hour" ]; then
        # Calculate next occurrence of that UTC hour
        local current_utc_date
        current_utc_date=$(date -u +%Y-%m-%dT)
        reset_epoch=$(date -u -d "${current_utc_date}${reset_hour}:00:00" +%s 2>/dev/null) || true
        if [ -n "$reset_epoch" ]; then
            # If reset hour has passed today, it's tomorrow
            if [ "$reset_epoch" -le "$now_epoch" ]; then
                reset_epoch=$((reset_epoch + 86400))
            fi
            sleep_secs=$((reset_epoch - now_epoch + 60))
            echo "$sleep_secs"
            return
        fi
    fi

    # Ultimate fallback: 5 hours
    echo "18060"
}

# Sleep until quota resets with countdown display
# Ctrl+C during sleep aborts the loop
sleep_until_reset() {
    local total_seconds="$1"
    local wake_time
    wake_time=$(date -d "+${total_seconds} seconds" '+%Y-%m-%d %H:%M:%S %Z')

    log_warn "Quota exhausted. Sleeping until reset..."
    log_info "Wake time: $wake_time (${total_seconds}s from now)"
    echo ""

    local remaining="$total_seconds"
    while [ "$remaining" -gt 0 ]; do
        local hours=$((remaining / 3600))
        local mins=$(( (remaining % 3600) / 60 ))
        local secs=$((remaining % 60))
        printf "\r  ⏳ Quota reset in %02d:%02d:%02d (Ctrl+C to abort) " "$hours" "$mins" "$secs"
        sleep 1
        remaining=$((remaining - 1))
    done
    printf "\r  ✅ Quota reset period elapsed. Resuming...                    \n"
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
        READY_COUNT=$($(get_bd_ready_cmd) 2>/dev/null | jq 'length // 0')

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
        if [ -n "$RALPH_SCOPE" ]; then
            bd ready --parent="$RALPH_SCOPE" 2>/dev/null | head -5 || true
        else
            bd ready 2>/dev/null | head -5 || true
        fi
        echo ""
    fi

    # Run Ralph iteration with selected prompt
    # -p: Headless mode (non-interactive, reads from stdin)
    # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
    # --output-format=stream-json: Structured output for logging/monitoring
    # --model opus: Primary agent uses Opus for complex reasoning
    # --verbose: Detailed execution logging

    LAST_EXIT=0
    ITER_START=$(date +%s)

    # Log iteration start if logging enabled
    if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
        log_event "iteration_start" "{\"iteration\":$ITERATION,\"issue_id\":\"${CURRENT_ISSUE:-none}\",\"mode\":\"$MODE\"}"
    fi

    # Replace template variables in prompt file and run claude
    # Always capture output to temp file for quota detection
    _ITER_OUTPUT_FILE="${_RALPH_PROJECT_STATE_DIR}/iter-output-$$.tmp"

    sed "s/\${RALPH_SCOPE}/${RALPH_SCOPE:-}/g" "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose 2>&1 | tee "$_ITER_OUTPUT_FILE" || LAST_EXIT=$?

    # Append to log file if logging enabled
    if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
        cat "$_ITER_OUTPUT_FILE" >> "$_RALPH_LOG_FILE"
    fi

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))

    # Log iteration end if logging enabled
    if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
        log_event "iteration_end" "{\"iteration\":$ITERATION,\"exit_code\":$LAST_EXIT,\"duration_seconds\":$ITER_DURATION}"
    fi

    # Check for quota exhaustion before normal exit handling
    if check_quota_exhaustion "$_ITER_OUTPUT_FILE"; then
        log_warn "Quota exhaustion detected (rate_limit error)"

        if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
            log_event "quota_exhausted" "{\"iteration\":$ITERATION,\"issue_id\":\"${CURRENT_ISSUE:-none}\"}"
        fi

        # Undo the attempt increment — quota hit isn't a real attempt
        if [ -n "${CURRENT_ISSUE:-}" ]; then
            decrement_attempts "$CURRENT_ISSUE"
        fi

        # Don't count this iteration toward max
        ITERATION=$((ITERATION - 1))

        # Extract error message for fallback parsing
        QUOTA_ERROR_MSG=$(grep '"error":"rate_limit"' "$_ITER_OUTPUT_FILE" | jq -r '.result // empty' 2>/dev/null | head -1) || QUOTA_ERROR_MSG=""

        QUOTA_SLEEP_SECS=$(get_quota_reset_seconds "$QUOTA_ERROR_MSG")

        if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
            log_event "quota_sleep_start" "{\"sleep_seconds\":$QUOTA_SLEEP_SECS}"
        fi

        rm -f "$_ITER_OUTPUT_FILE" 2>/dev/null || true
        sleep_until_reset "$QUOTA_SLEEP_SECS"

        if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
            log_event "quota_sleep_end" "{}"
        fi

        continue  # Skip beads sync / git push (nothing to sync)
    fi

    rm -f "$_ITER_OUTPUT_FILE" 2>/dev/null || true

    # Check if iteration was successful
    if [ "$LAST_EXIT" -ne 0 ]; then
        log_warn "Iteration ended with exit code $LAST_EXIT"
    else
        # Reset attempts on success (issue was likely closed)
        if [ -n "${CURRENT_ISSUE:-}" ]; then
            # Check if issue was closed
            # Handle both object and array responses from bd show --json
            ISSUE_STATUS=$(bd show "$CURRENT_ISSUE" --json 2>/dev/null | jq -r '(if type == "array" then .[0] else . end) | .status // "unknown"') || ISSUE_STATUS="unknown"
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
if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
    echo ""
    echo "Log file: $_RALPH_LOG_FILE"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Note: Attempt file is preserved externally for cross-session persistence
# To reset attempts, delete: $ATTEMPT_FILE
