#!/bin/bash
# Standalone test for hihy-session.sh - no framework, mirrors server/test_*.sh style.
# Drives a local mock command through the screen-backed session driver; no real server.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SH="${SCRIPT_DIR}/hihy-session.sh"

TEST_ROOT="$(mktemp -d)"
export HIHY_SESSION_NAME="hihy-test-$$"
export HIHY_SESSION_DIR="${TEST_ROOT}/session"

PASS=0
FAIL=0

cleanup() {
    bash "$SESSION_SH" stop >/dev/null 2>&1
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

assert_contains() {
    # assert_contains <haystack> <needle> <label>
    if printf '%s' "$1" | grep -q "$2"; then
        pass "$3"
    else
        fail "$3"
        echo "---- got (last 20 lines) ----"
        printf '%s\n' "$1" | tail -20
        echo "-----------------------------"
    fi
}

test_lifecycle() {
    echo "=== test_lifecycle ==="
    export HIHY_SESSION_CMD="sleep 300"

    if bash "$SESSION_SH" start >/dev/null 2>&1; then
        pass "start creates session"
    else
        fail "start creates session"
        return
    fi

    assert_contains "$(bash "$SESSION_SH" status)" "alive" "status reports alive"

    # start again must replace the old session, not error out
    if bash "$SESSION_SH" start >/dev/null 2>&1; then
        pass "start is idempotent (replaces stale session)"
    else
        fail "start is idempotent (replaces stale session)"
    fi
    assert_contains "$(bash "$SESSION_SH" status)" "alive" "status alive after restart"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    sleep 1
    if bash "$SESSION_SH" status >/dev/null 2>&1; then
        fail "status exits non-zero after stop"
    else
        pass "status exits non-zero after stop"
    fi

    if bash "$SESSION_SH" stop >/dev/null 2>&1; then
        pass "stop is safe when session already gone"
    else
        fail "stop is safe when session already gone"
    fi

    unset HIHY_SESSION_CMD
}

test_lifecycle

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
