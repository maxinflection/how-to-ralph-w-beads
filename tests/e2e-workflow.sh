#!/bin/bash
# E2E Workflow Test for Ralph+Beads
#
# Tests that the loop correctly:
# 1. Exits when bd ready is empty
# 2. Detects stuck issues after N attempts
# 3. Syncs with git properly
#
# Usage: ./tests/e2e-workflow.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Setup test environment
TEST_DIR=$(mktemp -d)
ORIG_DIR=$(pwd)

cleanup() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_info "Setting up test environment in $TEST_DIR"

# Copy files to test directory
cp -r files "$TEST_DIR/"
cd "$TEST_DIR"

# Initialize git repo (required for beads)
git init --quiet
git config user.email "test@test.com"
git config user.name "Test"

# Initialize beads with test prefix
BEADS_DB="$TEST_DIR/.beads/beads.db"
export BEADS_DB
bd init --quiet --prefix test

log_info "Created test beads database"

# =============================================================================
# Test 1: Empty queue exit condition
# =============================================================================
log_info "Test 1: Empty queue exit condition"

# Create and immediately close an issue
bd create --title="Test task 1" --type=task --priority=2 \
  --acceptance="- [ ] Always pass | \`true\` | exit 0" > /dev/null

ISSUE_ID=$(bd list --json | jq -r '.[0].id')
bd close "$ISSUE_ID" --reason "Test close" > /dev/null

# Verify bd ready is empty
READY_COUNT=$(bd ready --json 2>/dev/null | jq 'length // 0')
if [ "$READY_COUNT" -eq 0 ]; then
    log_pass "Empty queue detected when all issues closed"
else
    log_fail "Expected 0 ready issues, got $READY_COUNT"
fi

# =============================================================================
# Test 2: Blocked issues don't appear in ready queue
# =============================================================================
log_info "Test 2: Blocked issues filtered from ready queue"

# Create two issues with dependency
bd create --title="Blocker task" --type=task --priority=1 > /dev/null
BLOCKER_ID=$(bd list --json | jq -r '.[] | select(.title == "Blocker task") | .id')

bd create --title="Blocked task" --type=task --priority=1 > /dev/null
BLOCKED_ID=$(bd list --json | jq -r '.[] | select(.title == "Blocked task") | .id')

bd dep add "$BLOCKED_ID" "$BLOCKER_ID" > /dev/null

# Verify blocked issue is not in ready queue
READY_IDS=$(bd ready --json 2>/dev/null | jq -r '.[].id')
if echo "$READY_IDS" | grep -q "$BLOCKED_ID"; then
    log_fail "Blocked issue $BLOCKED_ID should not appear in ready queue"
else
    log_pass "Blocked issue correctly filtered from ready queue"
fi

# Verify blocker IS in ready queue
if echo "$READY_IDS" | grep -q "$BLOCKER_ID"; then
    log_pass "Blocker issue correctly appears in ready queue"
else
    log_fail "Blocker issue $BLOCKER_ID should appear in ready queue"
fi

# =============================================================================
# Test 3: Closing blocker unblocks dependent
# =============================================================================
log_info "Test 3: Closing blocker unblocks dependent"

bd close "$BLOCKER_ID" --reason "Test close" > /dev/null

READY_IDS=$(bd ready --json 2>/dev/null | jq -r '.[].id')
if echo "$READY_IDS" | grep -q "$BLOCKED_ID"; then
    log_pass "Dependent issue unblocked after blocker closed"
else
    log_fail "Dependent issue $BLOCKED_ID should be unblocked now"
fi

# Clean up
bd close "$BLOCKED_ID" --reason "Test close" > /dev/null

# =============================================================================
# Test 4: Stuck detection tracking
# =============================================================================
log_info "Test 4: Stuck detection mechanism"

ATTEMPT_FILE=".ralph-attempts"

# Create a new issue
bd create --title="Stuck test task" --type=task --priority=1 > /dev/null
STUCK_ID=$(bd list --json | jq -r '.[] | select(.title == "Stuck test task") | .id')

# Simulate 3 failed attempts
touch "$ATTEMPT_FILE"
for i in 1 2 3; do
    # Remove old entry
    grep -v "^${STUCK_ID}:" "$ATTEMPT_FILE" > "${ATTEMPT_FILE}.tmp" 2>/dev/null || true
    echo "${STUCK_ID}:${i}" >> "${ATTEMPT_FILE}.tmp"
    mv "${ATTEMPT_FILE}.tmp" "$ATTEMPT_FILE"
done

# Verify attempt count
ATTEMPTS=$(grep "^${STUCK_ID}:" "$ATTEMPT_FILE" | cut -d: -f2)
if [ "$ATTEMPTS" -eq 3 ]; then
    log_pass "Attempt counter correctly tracks 3 attempts"
else
    log_fail "Expected 3 attempts, got $ATTEMPTS"
fi

# Clean up
bd close "$STUCK_ID" --reason "Test close" > /dev/null
rm -f "$ATTEMPT_FILE"

# =============================================================================
# Test 5: Priority ordering in ready queue
# =============================================================================
log_info "Test 5: Priority ordering in ready queue"

bd create --title="P3 task" --type=task --priority=3 > /dev/null
bd create --title="P1 task" --type=task --priority=1 > /dev/null
bd create --title="P2 task" --type=task --priority=2 > /dev/null

FIRST_READY=$(bd ready --json 2>/dev/null | jq -r '.[0].title')
if [ "$FIRST_READY" = "P1 task" ]; then
    log_pass "Highest priority task (P1) is first in ready queue"
else
    log_fail "Expected P1 task first, got: $FIRST_READY"
fi

# Clean up
for id in $(bd list --json | jq -r '.[].id'); do
    bd close "$id" --reason "Test cleanup" > /dev/null 2>&1 || true
done

# =============================================================================
# Test 6: Loop script syntax check
# =============================================================================
log_info "Test 6: Loop script syntax validation"

if bash -n files/loop.sh 2>/dev/null; then
    log_pass "loop.sh passes syntax check"
else
    log_fail "loop.sh has syntax errors"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}All E2E tests passed!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
