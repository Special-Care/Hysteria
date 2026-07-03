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

write_mock() {
    # Simulates the remote side: ssh password prompt -> shell -> hihy menu
    # -> first install question -> success marker. Sleeps keep the screen
    # session alive long enough for the test to read the final output.
    cat > "${TEST_ROOT}/mock_remote.sh" <<'MOCK'
#!/bin/bash
printf "root@203.0.113.10's password: "
IFS= read -r pw
if [ "$pw" != "s3cret" ]; then
    echo ""
    echo "Permission denied, please try again."
    sleep 10
    exit 1
fi
echo ""
echo "Welcome to mock server"
printf 'root@mock:~# '
IFS= read -r cmd
echo "Downloading hihy..."
echo "1、安装Hysteria2"
printf '请选择: '
IFS= read -r choice
if [ "$choice" != "1" ]; then
    echo "unexpected menu choice: $choice"
    sleep 10
    exit 1
fi
echo "(1/13)请选择证书申请方式:"
printf '输入序号: '
IFS= read -r cert
echo "cert choice: $cert"
echo "安装成功,请查看下方配置详细信息"
sleep 30
MOCK
    chmod +x "${TEST_ROOT}/mock_remote.sh"
}

wait_for() {
    # wait_for <grep_pattern> [timeout_s]  -> prints the read snapshot that matched
    local pattern="$1" timeout="${2:-15}" out="" i=0
    while [ "$i" -lt $((timeout * 2)) ]; do
        out="$(bash "$SESSION_SH" read 2>/dev/null)"
        if printf '%s' "$out" | grep -q "$pattern"; then
            printf '%s' "$out"
            return 0
        fi
        sleep 0.5
        i=$((i+1))
    done
    printf '%s' "$out"
    return 1
}

test_full_install_loop() {
    echo "=== test_full_install_loop ==="
    write_mock
    export HIHY_SESSION_CMD="bash ${TEST_ROOT}/mock_remote.sh"

    bash "$SESSION_SH" start >/dev/null 2>&1 || { fail "start with mock"; return; }
    pass "start with mock"

    out="$(wait_for "password:")" || true
    assert_contains "$out" "password:" "read surfaces password prompt"

    printf '%s\n' "s3cret" | bash "$SESSION_SH" send-secret
    out="$(wait_for "root@mock")" || true
    assert_contains "$out" "Welcome to mock server" "send-secret answers password prompt"

    bash "$SESSION_SH" send "bash install.sh"
    out="$(wait_for "请选择")" || true
    assert_contains "$out" "1、安装Hysteria2" "menu appears after install command"

    bash "$SESSION_SH" send "1"
    out="$(wait_for "(1/13)")" || true
    assert_contains "$out" "(1/13)请选择证书申请方式" "install step 1 prompt is readable"

    bash "$SESSION_SH" send "3"
    out="$(wait_for "安装成功")" || true
    assert_contains "$out" "安装成功,请查看下方配置详细信息" "success marker visible"

    out="$(bash "$SESSION_SH" read all)"
    assert_contains "$out" "Welcome to mock server" "read all keeps full history"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    unset HIHY_SESSION_CMD
}

test_wrong_password() {
    echo "=== test_wrong_password ==="
    write_mock
    export HIHY_SESSION_CMD="bash ${TEST_ROOT}/mock_remote.sh"

    bash "$SESSION_SH" start >/dev/null 2>&1 || { fail "start with mock (wrong pw)"; return; }
    wait_for "password:" >/dev/null || true

    printf '%s\n' "wrong-password" | bash "$SESSION_SH" send-secret
    out="$(wait_for "Permission denied")" || true
    assert_contains "$out" "Permission denied" "auth failure is detectable via read"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    unset HIHY_SESSION_CMD
}

test_lifecycle
test_full_install_loop
test_wrong_password

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
