# ---------------------------------------------------------------------------
# Active-protocol state model (multi-protocol foundation)
#
# A hihy install runs exactly one protocol at a time. The `active` file records
# which protocol/core is installed so every lifecycle command can dispatch to
# the right core. Existing Hysteria2-only installs predate this file, so the
# getters fall back to detecting the legacy config.yaml and reporting hysteria.
# ---------------------------------------------------------------------------
HIHY_ACTIVE_FILE="${HIHY_ACTIVE_FILE:-$HIHY_ROOT_DIR/active}"
HIHY_SYSCTL_FILE="${HIHY_SYSCTL_FILE:-/etc/sysctl.d/99-hihy.conf}"

writeActiveState() {
    # Args: one or more key=value pairs, e.g. writeActiveState "protocol=vless" "core=sing-box"
    local active_file="$HIHY_ACTIVE_FILE"
    local old_umask
    old_umask=$(umask)
    umask 077
    mkdir -p "$(dirname "$active_file")"
    : > "$active_file"
    local pair
    for pair in "$@"; do
        printf '%s\n' "$pair" >> "$active_file"
    done
    umask "$old_umask"
}

getActiveValue() {
    # Args: $1 key, $2 optional active-file path (defaults to $HIHY_ACTIVE_FILE).
    local key="$1"
    local active_file="${2:-$HIHY_ACTIVE_FILE}"
    [ -f "$active_file" ] || return 0
    grep -m1 "^${key}=" "$active_file" | cut -d '=' -f 2- || true
}

getActiveCore() {
    # Optional $1: active-file override. Echoes hysteria | sing-box | "".
    local active_file="${1:-$HIHY_ACTIVE_FILE}"
    local core
    core=$(getActiveValue "core" "$active_file")
    if [ -n "$core" ]; then
        printf '%s' "$core"
        return 0
    fi
    # Back-compat: legacy Hysteria2-only install has no active file.
    if [ -f "$HIHY_ROOT_DIR/conf/config.yaml" ]; then
        printf 'hysteria'
        return 0
    fi
    printf ''
}

getActiveProtocol() {
    # Optional $1: active-file override. Echoes hysteria2 | vless | vmess | trojan | "".
    local active_file="${1:-$HIHY_ACTIVE_FILE}"
    local proto
    proto=$(getActiveValue "protocol" "$active_file")
    if [ -n "$proto" ]; then
        printf '%s' "$proto"
        return 0
    fi
    if [ -f "$HIHY_ROOT_DIR/conf/config.yaml" ]; then
        printf 'hysteria2'
        return 0
    fi
    printf ''
}

