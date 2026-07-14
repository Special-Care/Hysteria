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

assert_file_contains() {
    local path="$1"
    local expected="$2"
    local message="$3"

    if ! grep -Fq "$expected" "$path"; then
        printf 'ASSERT FAILED: %s\nMissing text: %s\nFile: %s\n' "$message" "$expected" "$path" >&2
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

test_absent_key_in_existing_file_does_not_abort_under_errexit() {
    reset_state
    writeActiveState "protocol=vless"   # deliberately no core= key
    # Under `set -e`+`pipefail`, a bare assignment whose command substitution
    # returns nonzero aborts the whole script. These must NOT abort.
    local val
    val=$(getActiveValue core)
    assert_equals "" "$val" "absent key in an existing active file yields empty without aborting"
    local resolved
    resolved=$(getActiveCore)
    assert_equals "" "$resolved" "getActiveCore with no core key (and no config.yaml) is empty, no abort"
}

test_singbox_arch_mapping() {
    assert_equals "amd64" "$(getSingboxArch x86_64)" "x86_64 -> amd64"
    assert_equals "arm64" "$(getSingboxArch aarch64)" "aarch64 -> arm64"
    assert_equals "armv7" "$(getSingboxArch armv7l)" "armv7l -> armv7"
    assert_equals "386" "$(getSingboxArch i686)" "i686 -> 386"
    if getSingboxArch sparc64 >/dev/null 2>&1; then
        printf 'ASSERT FAILED: unsupported arch should return non-zero\n' >&2
        exit 1
    fi
}

test_singbox_download_extracts_binary() {
    reset_state
    local sb_dir="sing-box-1.13.14-linux-amd64"
    local url_log="$TEST_ROOT/singbox-url.log"
    : > "$url_log"

    # Mock wget AND curl (downloadToFile prefers wget) to synthesize a release
    # tarball containing <dir>/sing-box, matching the real archive layout.
    cat > "$MOCK_BIN/wget" <<EOF
#!/bin/sh
out=""; url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -O|-o) out="\$2"; shift 2 ;;
    -q|-fsSL) shift ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
printf '%s\n' "\$url" >> "${url_log}"
work=\$(mktemp -d)
mkdir -p "\$work/${sb_dir}"
printf '#!/bin/sh\necho sing-box version 1.13.14\n' > "\$work/${sb_dir}/sing-box"
chmod +x "\$work/${sb_dir}/sing-box"
tar -czf "\$out" -C "\$work" "${sb_dir}"
rm -rf "\$work"
EOF
    cp "$MOCK_BIN/wget" "$MOCK_BIN/curl"
    chmod +x "$MOCK_BIN/wget" "$MOCK_BIN/curl"

    export HIHY_SINGBOX_VERSION="v1.13.14"
    local saved_path="$PATH"
    export PATH="$MOCK_BIN:$PATH"

    # Force the amd64 code path regardless of the dev machine's real arch,
    # saving the real function so we can restore it (unset -f would delete it
    # for later tests in this file — bash function overrides aren't scoped).
    local orig_getSingboxArch
    orig_getSingboxArch=$(declare -f getSingboxArch)
    getSingboxArch() { printf 'amd64'; }

    if ! downloadSingboxCore >/dev/null 2>&1; then
        eval "$orig_getSingboxArch"
        export PATH="$saved_path"
        printf 'ASSERT FAILED: downloadSingboxCore should succeed with a valid tarball\n' >&2
        exit 1
    fi
    eval "$orig_getSingboxArch"
    export PATH="$saved_path"

    if [ ! -x "$HIHY_SINGBOX_BIN" ]; then
        printf 'ASSERT FAILED: sing-box binary should be installed and executable at %s\n' "$HIHY_SINGBOX_BIN" >&2
        exit 1
    fi
    assert_equals "sing-box version 1.13.14" "$("$HIHY_SINGBOX_BIN")" "installed binary should be the extracted one"
    assert_file_contains "$url_log" "/releases/download/v1.13.14/${sb_dir}.tar.gz" "download should request the pinned sing-box tarball URL"
}

test_write_and_read_active_state
test_active_core_and_protocol_from_file
test_legacy_hysteria_install_has_no_active_file
test_clean_system_has_empty_core
test_absent_key_in_existing_file_does_not_abort_under_errexit
test_singbox_arch_mapping
test_singbox_download_extracts_binary

printf 'All multi-protocol state tests passed.\n'
