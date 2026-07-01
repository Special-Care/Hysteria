#!/bin/bash
set -euo

# Set C locale to avoid tr encoding issues on macOS
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEST_ROOT=$(mktemp -d)

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

# 让被 source 的生产脚本把可写副作用落到临时目录(不触碰真实 /etc)。
export HIHY_ROOT_DIR="$TEST_ROOT/hihy"
export HIHY_BIN_LINK="$TEST_ROOT/bin/hihy"
export HIHY_YQ_BIN="$TEST_ROOT/bin/yq"
export printN=""

source "$SCRIPT_DIR/hy2.sh"

assert_equals() {
    local expected="$1" actual="$2" message="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'ASSERT FAILED: %s\nExpected: %s\nActual: %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_true() {
    local message="$2"
    if ! eval "$1"; then
        printf 'ASSERT FAILED (expected success): %s\n' "$message" >&2
        exit 1
    fi
}

assert_false() {
    local message="$2"
    if eval "$1"; then
        printf 'ASSERT FAILED (expected failure): %s\n' "$message" >&2
        exit 1
    fi
}

test_generate_password_shape() {
    local p
    p=$(generate_password)
    assert_equals "8" "${#p}" "generate_password should yield 8 chars"
    if ! [[ "$p" =~ ^[A-Za-z0-9]{8}$ ]]; then
        printf 'ASSERT FAILED: password %s not alnum-8\n' "$p" >&2
        exit 1
    fi
}

test_is_valid_username() {
    assert_true  'isValidUsername user1'      "user1 valid"
    assert_true  'isValidUsername A_b-9'      "A_b-9 valid"
    assert_false 'isValidUsername "bad:name"' "colon rejected"
    assert_false 'isValidUsername "bad@name"' "at rejected"
    assert_false 'isValidUsername "a b"'      "space rejected"
    assert_false 'isValidUsername ""'         "empty rejected"
}

test_is_valid_password() {
    assert_true  'isValidPassword "Abc123_.~-"' "url-safe set valid"
    assert_false 'isValidPassword "bad@pass"'   "at rejected"
    assert_false 'isValidPassword "with space"' "space rejected"
    assert_false 'isValidPassword ""'           "empty rejected"
}

test_generate_password_shape
test_is_valid_username
test_is_valid_password

printf 'All multi-user tests passed.\n'
