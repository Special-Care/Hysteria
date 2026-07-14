#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEST_ROOT=$(mktemp -d)
TEST_ETC="$TEST_ROOT/etc"
TEST_BIN="$TEST_ROOT/bin"
MOCK_BIN="$TEST_ROOT/mock-bin"
ORIGINAL_PATH="$PATH"

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

mkdir -p "$TEST_ETC" "$TEST_BIN" "$MOCK_BIN"

export HIHY_ROOT_DIR="$TEST_ETC/hihy"
export HIHY_BIN_LINK="$TEST_BIN/hihy"
export HIHY_YQ_BIN="$TEST_BIN/yq"
export HIHY_ACTIVE_FILE="$HIHY_ROOT_DIR/active"
export HIHY_SYSCTL_FILE="$TEST_ROOT/99-hihy.conf"
export HIHY_SINGBOX_BIN="$HIHY_ROOT_DIR/bin/sing-box"
export printN=""

source "$SCRIPT_DIR/hy2.sh"

assert_equals() {
    local expected="$1" actual="$2" message="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'ASSERT FAILED: %s\nExpected: %s\nActual: %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_mode() {
    local path="$1" expected="$2" message="$3" actual
    actual=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
    if [ "$expected" != "$actual" ]; then
        printf 'ASSERT FAILED: %s\nExpected mode: %s\nActual mode: %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

reset_state() { rm -rf "$HIHY_ROOT_DIR"; }

test_write_and_read_active_state() {
    reset_state
    writeActiveState "protocol=vless" "core=sing-box" "transport=tcp-reality"
    assert_equals "vless" "$(getActiveValue protocol)" "protocol should round-trip"
    assert_equals "sing-box" "$(getActiveValue core)" "core should round-trip"
    assert_equals "tcp-reality" "$(getActiveValue transport)" "transport should round-trip"
    assert_equals "" "$(getActiveValue missing)" "absent key should be empty"
    assert_file_mode "$HIHY_ACTIVE_FILE" "600" "active file should be private (secrets may appear later)"
}

test_active_core_and_protocol_from_file() {
    reset_state
    writeActiveState "protocol=trojan" "core=sing-box"
    assert_equals "sing-box" "$(getActiveCore)" "core read from active file"
    assert_equals "trojan" "$(getActiveProtocol)" "protocol read from active file"
}

test_legacy_hysteria_install_has_no_active_file() {
    reset_state
    mkdir -p "$HIHY_ROOT_DIR/conf"
    touch "$HIHY_ROOT_DIR/conf/config.yaml"
    assert_equals "hysteria" "$(getActiveCore)" "legacy config.yaml implies hysteria core"
    assert_equals "hysteria2" "$(getActiveProtocol)" "legacy config.yaml implies hysteria2 protocol"
}

test_clean_system_has_empty_core() {
    reset_state
    assert_equals "" "$(getActiveCore)" "no install => empty core"
    assert_equals "" "$(getActiveProtocol)" "no install => empty protocol"
}

test_write_and_read_active_state
test_active_core_and_protocol_from_file
test_legacy_hysteria_install_has_no_active_file
test_clean_system_has_empty_core

printf 'All multi-protocol state tests passed.\n'
