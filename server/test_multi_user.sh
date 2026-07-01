#!/bin/bash
set -eu

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

make_userpass_config() {
    local file="$1"
    cat > "$file" <<'YAML'
auth:
  type: userpass
  userpass:
    alice: alicepass
trafficStats:
  listen: 127.0.0.1:12345
  secret: traffic-secret-xyz
YAML
}

test_userpass_list_and_count() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    assert_equals "alice" "$(userpassListUsers "$f")" "single-user list"
    assert_equals "1" "$(userpassCountUsers "$f")" "count is 1"
}

test_userpass_add_and_get() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    userpassAddUser "$f" "bob" "bobpass"
    assert_equals "bobpass" "$(getUserPassword "$f" bob)" "added user readable"
    assert_equals "2" "$(userpassCountUsers "$f")" "count is 2 after add"
}

test_userpass_exists() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    assert_true  'userpassUserExists "'"$f"'" alice'  "alice exists"
    assert_false 'userpassUserExists "'"$f"'" nobody' "nobody absent"
}

test_userpass_delete() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    userpassAddUser "$f" "bob" "bobpass"
    userpassDeleteUser "$f" "alice"
    assert_equals "null" "$(getUserPassword "$f" alice)" "deleted user gone"
    assert_equals "bob" "$(userpassListUsers "$f")" "remaining user is bob"
}

# strenv() must keep nasty password literal and not inject new YAML keys.
test_userpass_injection_safe() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    userpassAddUser "$f" "carol" 'p") | .hacked = "x'
    assert_equals 'p") | .hacked = "x' "$(getUserPassword "$f" carol)" "special chars stored literally"
    assert_equals "null" "$(yq eval '.hacked' "$f")" "no top-level injection"
}

test_traffic_secret_userpass() {
    local f="$TEST_ROOT/config.yaml"; make_userpass_config "$f"
    assert_equals "traffic-secret-xyz" "$(getTrafficStatsSecret "$f")" "reads trafficStats.secret"
}

test_traffic_secret_fallback() {
    local f="$TEST_ROOT/legacy.yaml"
    cat > "$f" <<'YAML'
auth:
  type: password
  password: oldsecret
YAML
    assert_equals "oldsecret" "$(getTrafficStatsSecret "$f")" "falls back to auth.password"
}

test_setconfig_writes_userpass() {
    local s="$SCRIPT_DIR/hy2.sh"
    grep -Fq 'addOrUpdateYaml "$yaml_file" "auth.type" "userpass"' "$s" \
        || { echo 'FAIL: auth.type not set to userpass' >&2; exit 1; }
    grep -Fq 'userpassAddUser "$yaml_file"' "$s" \
        || { echo 'FAIL: first user not written via userpassAddUser' >&2; exit 1; }
    if grep -Fq 'addOrUpdateYaml "$yaml_file" "auth.type" "password"' "$s"; then
        echo 'FAIL: legacy auth.type password write still present' >&2; exit 1
    fi
    grep -Fq 'addOrUpdateYaml "$yaml_file" "trafficStats.secret" "${traffic_secret}"' "$s" \
        || { echo 'FAIL: trafficStats.secret not decoupled' >&2; exit 1; }
}

test_usercontrol_wiring() {
    local s="$SCRIPT_DIR/hy2.sh"
    grep -Eq '^userControl\(\)' "$s"        || { echo 'FAIL: userControl() missing' >&2; exit 1; }
    grep -Eq '^selectHysteriaUser\(\)' "$s" || { echo 'FAIL: selectHysteriaUser() missing' >&2; exit 1; }
    grep -Fq '16) userControl; exit 0' "$s" || { echo 'FAIL: menu() case 16 missing' >&2; exit 1; }
    grep -Fq 'userControl|16)' "$s"         || { echo 'FAIL: dispatcher case 16 missing' >&2; exit 1; }
    grep -Fq '16) 多用户管理' "$s"          || { echo 'FAIL: show_menu entry 16 missing' >&2; exit 1; }
}

test_export_mode_aware() {
    local s="$SCRIPT_DIR/hy2.sh"
    grep -Fq 'authType=$(getYamlValue "/etc/hihy/conf/config.yaml" "auth.type")' "$s" \
        || { echo 'FAIL: generate_client_config not mode-aware' >&2; exit 1; }
    grep -Fq 'auth_secret="${selected_user}:${selected_pass}"' "$s" \
        || { echo 'FAIL: userpass credential not composed' >&2; exit 1; }
    grep -Fq 'generateMetaYaml "${auth_secret}" "${userTag}"' "$s" \
        || { echo 'FAIL: generateMetaYaml not called with args' >&2; exit 1; }
    grep -Fq 'Hy2-${remarks}${userTag}-v2rayN.yaml' "$s" \
        || { echo 'FAIL: client filename not user-tagged' >&2; exit 1; }
}

test_validator_length_boundaries() {
    local u32 u33 p64 p65
    u32=$(printf 'a%.0s' $(seq 1 32)); u33=$(printf 'a%.0s' $(seq 1 33))
    p64=$(printf 'a%.0s' $(seq 1 64)); p65=$(printf 'a%.0s' $(seq 1 65))
    assert_true  "isValidUsername \"$u32\"" "32-char username accepted"
    assert_false "isValidUsername \"$u33\"" "33-char username rejected"
    assert_true  "isValidPassword \"$p64\"" "64-char password accepted"
    assert_false "isValidPassword \"$p65\"" "65-char password rejected"
}

test_userpass_absent_node() {
    local f="$TEST_ROOT/legacy2.yaml"
    cat > "$f" <<'YAML'
auth:
  type: password
  password: single
YAML
    assert_equals "0" "$(userpassCountUsers "$f")" "absent userpass node counts as 0"
    assert_false 'userpassUserExists "'"$f"'" anyone' "no user exists in legacy config"
}

test_traffic_secret_empty_falls_back() {
    local f="$TEST_ROOT/empty.yaml"
    cat > "$f" <<'YAML'
auth:
  type: password
  password: fallbackpass
trafficStats:
  secret: ""
YAML
    assert_equals "fallbackpass" "$(getTrafficStatsSecret "$f")" "empty trafficStats.secret falls back to auth.password"
}

test_generate_password_shape
test_is_valid_username
test_is_valid_password
test_userpass_list_and_count
test_userpass_add_and_get
test_userpass_exists
test_userpass_delete
test_userpass_injection_safe
test_traffic_secret_userpass
test_traffic_secret_fallback
test_setconfig_writes_userpass
test_usercontrol_wiring
test_export_mode_aware
test_validator_length_boundaries
test_userpass_absent_node
test_traffic_secret_empty_falls_back

printf 'All multi-user tests passed.\n'
