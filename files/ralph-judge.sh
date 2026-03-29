#!/usr/bin/env bash
# shellcheck disable=SC2153  # Variables (ITERATION, MODE, etc.) come from loop.sh caller
# ralph-judge.sh — Inter-iteration LLM judge for the Ralph loop
#
# Evaluates iteration output between iterations to detect:
# - Spinning (consecutive non-productive iterations)
# - Invalid closures (acceptance criteria not truly verified)
# - Mode switch needs (stuck agent should enter plan mode)
#
# On by default. Set RALPH_JUDGE=0 to disable.
#
# Requires: claude CLI, jq, bd

# Configuration (override via environment)
RALPH_JUDGE="${RALPH_JUDGE:-1}"
RALPH_JUDGE_MODEL="${RALPH_JUDGE_MODEL:-haiku}"
RALPH_JUDGE_BUDGET="${RALPH_JUDGE_BUDGET:-0.05}"
RALPH_JUDGE_TIMEOUT="${RALPH_JUDGE_TIMEOUT:-30}"

# Internal state
_RALPH_JUDGE_HISTORY_FILE=""
_JUDGE_CONSECUTIVE_NONPRODUCTIVE=0
_JUDGE_LAST_REASON=""
_JUDGE_PLAN_OVERRIDE=0

# Initialize judge state. Call once at loop startup.
init_judge() {
    if [ "${RALPH_JUDGE}" = "0" ]; then
        return
    fi

    _RALPH_JUDGE_HISTORY_FILE=$(get_judge_history_file)
    _JUDGE_CONSECUTIVE_NONPRODUCTIVE=0
    _JUDGE_LAST_REASON=""
    _JUDGE_PLAN_OVERRIDE=0
}

# Check if an iteration was productive (had edits, writes, tests, or closures).
# Returns 0 if productive, 1 if not.
_judge_is_productive() {
    local output_file="$1"
    [ -f "$output_file" ] || return 1

    # Look for Edit/Write tool_use blocks or bd close / test commands in Bash tool_use
    if jq -e 'select(.type=="assistant") | .message.content[]? |
        select(
            (.type=="tool_use" and (.name=="Edit" or .name=="Write")) or
            (.type=="tool_use" and .name=="Bash" and (.input.command | test("bd close|pytest|cargo test|npm test|go test")))
        )' "$output_file" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Extract issue IDs from bd close commands in stream-json output.
# Outputs newline-separated issue IDs (may be empty).
_judge_extract_closures() {
    local output_file="$1"
    [ -f "$output_file" ] || return

    jq -r 'select(.type=="assistant") | .message.content[]? |
        select(.type=="tool_use" and .name=="Bash" and (.input.command | test("bd close"))) |
        .input.command' "$output_file" 2>/dev/null |
        grep -oE 'bd close [a-zA-Z0-9._-]+' |
        sed 's/bd close //' |
        sort -u
}

# Extract the last N meaningful lines from stream-json for judge context.
# Filters to assistant text thoughts and tool_use summaries.
_judge_extract_tail() {
    local output_file="$1"
    local n_lines="${2:-150}"
    [ -f "$output_file" ] || return

    jq -r 'select(.type=="assistant") | .message.content[]? |
        if .type=="text" then .text
        elif .type=="tool_use" then "[tool: \(.name)] \((.input.command // (.input | tostring))[:120])"
        else empty end' "$output_file" 2>/dev/null |
        tail -n "$n_lines"
}

# Get acceptance criteria for an issue. Returns compact text.
_judge_get_issue_ac() {
    local issue_id="$1"
    [ -n "$issue_id" ] || return

    bd show "$issue_id" --json 2>/dev/null |
        jq -r '(if type == "array" then .[0] else . end) |
            "Title: \(.title // "unknown")\nAcceptance Criteria:\n\(.acceptance_criteria // "None specified")"' 2>/dev/null ||
        echo "Issue context unavailable"
}

# Build the full context document piped to the judge's stdin.
# Uses variables from the calling scope.
_judge_build_context() {
    local output_file="$1"
    local iteration="$2"
    local mode="$3"
    local duration="$4"
    local exit_code="$5"
    local current_issue="$6"

    cat <<CONTEXT
## Iteration #${iteration} (${mode} mode, ${duration}s, exit ${exit_code})
Issue: ${current_issue:-none}

## Current Issue Context
$(_judge_get_issue_ac "${current_issue}")

## Closures This Iteration
$(_judge_extract_closures "$output_file" | sed 's/^/- /' || echo "None")

## Productivity
Consecutive non-productive iterations: ${_JUDGE_CONSECUTIVE_NONPRODUCTIVE}
$([ "$_JUDGE_CONSECUTIVE_NONPRODUCTIVE" -ge 3 ] && echo "WARNING: ${_JUDGE_CONSECUTIVE_NONPRODUCTIVE} consecutive non-productive iterations — consider EXIT verdict")

## Recent Judge History
$(tail -5 "$_RALPH_JUDGE_HISTORY_FILE" 2>/dev/null || echo "No prior history")

## Iteration Activity (last 150 lines)
$(_judge_extract_tail "$output_file" 150)
CONTEXT
}

# Parse judge verdict from raw LLM output.
# Sets _JUDGE_LAST_REASON. Returns verdict string via stdout.
_judge_parse_verdict() {
    local raw_output="$1"

    # Extract verdict line (case-insensitive match)
    local verdict
    verdict=$(echo "$raw_output" | grep -iE '^VERDICT:\s*' | head -1 | sed -E 's/^VERDICT:\s*//i' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    # Extract reason
    _JUDGE_LAST_REASON=$(echo "$raw_output" | grep -iE '^REASON:\s*' | head -1 | sed -E 's/^REASON:\s*//i')

    # Validate verdict
    case "$verdict" in
        continue|exit|plan)
            echo "$verdict" ;;
        reopen:*)
            # Validate the issue ID part is non-empty
            local reopen_id="${verdict#reopen:}"
            if [ -n "$reopen_id" ]; then
                echo "$verdict"
            else
                echo "continue"
            fi
            ;;
        *)
            echo "continue" ;;
    esac
}

# Main judge entry point. Called from loop.sh after each iteration.
# Returns verdict string: continue, exit, plan, or reopen:<id>
run_judge() {
    local output_file="$1"

    # Guard: disabled
    if [ "${RALPH_JUDGE}" = "0" ]; then
        echo "continue"
        return
    fi

    # Update productivity counter
    if _judge_is_productive "$output_file"; then
        _JUDGE_CONSECUTIVE_NONPRODUCTIVE=0
    else
        _JUDGE_CONSECUTIVE_NONPRODUCTIVE=$((_JUDGE_CONSECUTIVE_NONPRODUCTIVE + 1))
    fi

    # Build context and call judge
    local judge_prompt_file="${SCRIPT_DIR}/PROMPT_judge.md"
    if [ ! -f "$judge_prompt_file" ]; then
        log_warn "Judge prompt not found: $judge_prompt_file"
        echo "continue"
        return
    fi

    local context
    context=$(_judge_build_context "$output_file" "$ITERATION" "$MODE" "$ITER_DURATION" "$LAST_EXIT" "$CURRENT_ISSUE")

    local raw_output
    raw_output=$(echo "$context" | timeout "$RALPH_JUDGE_TIMEOUT" \
        claude -p \
            --model "$RALPH_JUDGE_MODEL" \
            --system-prompt "$(cat "$judge_prompt_file")" \
            --max-budget-usd "$RALPH_JUDGE_BUDGET" \
            --output-format json 2>/dev/null |
        jq -r '.result // empty' 2>/dev/null) || true

    # Handle timeout or failure
    if [ -z "$raw_output" ]; then
        _JUDGE_LAST_REASON="Judge call failed or timed out"
        _judge_append_history "continue" "Judge call failed or timed out" ""
        echo "continue"
        return
    fi

    # Parse verdict
    local verdict
    verdict=$(_judge_parse_verdict "$raw_output")

    # Extract closures for history record
    local closures
    closures=$(_judge_extract_closures "$output_file" | paste -sd, - 2>/dev/null || echo "")

    # Append to history
    _judge_append_history "$verdict" "$_JUDGE_LAST_REASON" "$closures"

    # Log if logging enabled
    if [ "$RALPH_LOG" = "1" ] && [ -n "$_RALPH_LOG_FILE" ]; then
        local escaped_reason
        escaped_reason=$(echo "$_JUDGE_LAST_REASON" | jq -Rs '.' 2>/dev/null || echo '""')
        log_event "judge_verdict" "{\"iteration\":$ITERATION,\"verdict\":\"$verdict\",\"reason\":$escaped_reason,\"consecutive_nonproductive\":$_JUDGE_CONSECUTIVE_NONPRODUCTIVE}"
    fi

    echo "$verdict"
}

# Append a verdict record to judge history.
_judge_append_history() {
    local verdict="$1"
    local reason="$2"
    local closures="$3"

    [ -n "$_RALPH_JUDGE_HISTORY_FILE" ] || return

    local timestamp
    timestamp=$(date -Iseconds)

    local escaped_reason
    escaped_reason=$(echo "$reason" | jq -Rs '.' 2>/dev/null || echo '""')

    printf '{"timestamp":"%s","iteration":%d,"issue_id":"%s","verdict":"%s","reason":%s,"closures":"%s","consecutive_nonproductive":%d}\n' \
        "$timestamp" "${ITERATION:-0}" "${CURRENT_ISSUE:-none}" "$verdict" "$escaped_reason" "$closures" "$_JUDGE_CONSECUTIVE_NONPRODUCTIVE" \
        >> "$_RALPH_JUDGE_HISTORY_FILE"
}
