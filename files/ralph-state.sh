#!/bin/bash
# Ralph State Management - External state directory and logging utilities
#
# This library manages Ralph loop state outside the project directory for "invisibility":
# - Attempt tracking (moved from .ralph-attempts)
# - Loop output logging (opt-in via RALPH_LOG=1)
# - Project identification via git remote URL hash
#
# State directory: ${RALPH_STATE_DIR:-~/.local/state/ralph}/projects/<project-hash>/
#
# Usage: source this file in loop.sh
#   source "${SCRIPT_DIR}/ralph-state.sh"
#   init_ralph_state
#   ATTEMPT_FILE=$(get_attempts_file)
#   LOG_FILE=$(get_log_file)

set -euo pipefail

# Configuration with defaults
RALPH_STATE_DIR="${RALPH_STATE_DIR:-${HOME}/.local/state/ralph}"
RALPH_LOG="${RALPH_LOG:-0}"
RALPH_LOG_RETENTION="${RALPH_LOG_RETENTION:-10}"  # Keep last N logs

# Internal state (set by init_ralph_state)
_RALPH_PROJECT_ID=""
_RALPH_PROJECT_STATE_DIR=""
_RALPH_LOG_FILE=""

# Get a stable project identifier from git remote URL or path
# Returns 12-char hash of the remote URL, or path if no remote
get_project_id() {
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

    if [ -n "$remote_url" ]; then
        # Use remote URL for stable cross-clone identification
        echo -n "$remote_url" | sha256sum | cut -c1-12
    else
        # Fallback to absolute path hash for local-only repos
        local abs_path
        abs_path=$(pwd -P)
        echo -n "$abs_path" | sha256sum | cut -c1-12
    fi
}

# Get the state directory for the current project, creating it if needed
get_project_state_dir() {
    local project_id="${1:-$_RALPH_PROJECT_ID}"
    local state_dir="${RALPH_STATE_DIR}/projects/${project_id}"

    if [ ! -d "$state_dir" ]; then
        mkdir -p "$state_dir"
        mkdir -p "${state_dir}/logs"

        # Write metadata for debugging/discovery
        cat > "${state_dir}/metadata.json" << EOF
{
  "project_id": "${project_id}",
  "project_path": "$(pwd -P)",
  "remote_url": "$(git config --get remote.origin.url 2>/dev/null || echo 'none')",
  "created_at": "$(date -Iseconds)"
}
EOF
    fi

    echo "$state_dir"
}

# Get path to external attempts file
get_attempts_file() {
    local state_dir="${1:-$_RALPH_PROJECT_STATE_DIR}"
    echo "${state_dir}/attempts.txt"
}

# Get path to current log file (timestamped)
# Only creates a log file if RALPH_LOG=1
get_log_file() {
    if [ "$RALPH_LOG" != "1" ]; then
        echo ""
        return
    fi

    local state_dir="${1:-$_RALPH_PROJECT_STATE_DIR}"
    local timestamp
    timestamp=$(date +%Y-%m-%dT%H-%M-%S)
    echo "${state_dir}/logs/${timestamp}.log"
}

# Clean old log files, keeping the most recent N
clean_old_logs() {
    local state_dir="${1:-$_RALPH_PROJECT_STATE_DIR}"
    local keep="${2:-$RALPH_LOG_RETENTION}"
    local logs_dir="${state_dir}/logs"

    if [ ! -d "$logs_dir" ]; then
        return
    fi

    # Count log files
    local count
    count=$(find "$logs_dir" -maxdepth 1 -name "*.log" -type f 2>/dev/null | wc -l)

    if [ "$count" -gt "$keep" ]; then
        # Delete oldest files beyond retention limit
        # Sort by name (timestamp format ensures chronological order)
        find "$logs_dir" -maxdepth 1 -name "*.log" -type f | \
            sort | head -n "$((count - keep))" | \
            xargs rm -f 2>/dev/null || true
    fi
}

# Write a metadata event to the log file
# Usage: log_event "iteration_start" '{"iteration": 1, "issue_id": "bd-abc"}'
log_event() {
    local event_type="$1"
    local data="${2:-"{}"}"
    local log_file="${3:-$_RALPH_LOG_FILE}"

    if [ -z "$log_file" ] || [ "$RALPH_LOG" != "1" ]; then
        return
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    # Output JSONL format
    printf '{"type":"loop_meta","event":"%s","timestamp":"%s","data":%s}\n' \
        "$event_type" "$timestamp" "$data" >> "$log_file"
}

# Check for legacy .ralph-attempts file and warn
check_legacy_attempts() {
    if [ -f ".ralph-attempts" ]; then
        echo -e "\033[1;33m[WARN]\033[0m Legacy .ralph-attempts file found in project directory"
        echo "       Ralph now stores state externally at: $_RALPH_PROJECT_STATE_DIR"
        echo "       You can safely delete .ralph-attempts"
        echo ""
    fi
}

# Initialize ralph state - call this at the start of loop.sh
init_ralph_state() {
    _RALPH_PROJECT_ID=$(get_project_id)
    _RALPH_PROJECT_STATE_DIR=$(get_project_state_dir "$_RALPH_PROJECT_ID")

    # Initialize log file if logging enabled
    if [ "$RALPH_LOG" = "1" ]; then
        _RALPH_LOG_FILE=$(get_log_file "$_RALPH_PROJECT_STATE_DIR")
        clean_old_logs "$_RALPH_PROJECT_STATE_DIR"
    fi

    # Ensure attempts file exists
    touch "$(get_attempts_file "$_RALPH_PROJECT_STATE_DIR")"

    # Check for and warn about legacy files
    check_legacy_attempts
}

# Export state information for use in loop.sh
get_ralph_state_info() {
    echo "Project ID:    $_RALPH_PROJECT_ID"
    echo "State dir:     $_RALPH_PROJECT_STATE_DIR"
    if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
        echo "Log file:      $_RALPH_LOG_FILE"
    else
        echo "Logging:       disabled (set RALPH_LOG=1 to enable)"
    fi
}
