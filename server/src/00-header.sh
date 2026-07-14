#!/bin/bash
hihyV="ver1.04-d"
# Sanitize PATH so we always resolve system binaries from trusted locations,
# regardless of whatever environment the operator's shell was launched in.
# Keep `hihyV` on line 2 — getLatestHihyVersion in older installed copies
# of hihy parses the remote script by `sed -n '2p'`.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"

HIHY_ROOT_DIR="${HIHY_ROOT_DIR:-/etc/hihy}"
HIHY_BIN_LINK="${HIHY_BIN_LINK:-/usr/bin/hihy}"
HIHY_YQ_BIN="${HIHY_YQ_BIN:-/usr/bin/yq}"
HIHY_PID_FILE="${HIHY_PID_FILE:-/var/run/hihy.pid}"
HIHY_RC_LOCAL="${HIHY_RC_LOCAL:-/etc/rc.local}"
HIHY_REMOTE_SCRIPT_URL="${HIHY_REMOTE_SCRIPT_URL:-https://raw.githubusercontent.com/Special-Care/Hysteria/refs/heads/main/server/hy2.sh}"
HIHY_REMOTE_SCRIPT_MIRROR_URL="${HIHY_REMOTE_SCRIPT_MIRROR_URL:-https://cdn.jsdelivr.net/gh/Special-Care/Hysteria@main/server/hy2.sh}"
HIHY_VERSION_STATUS_FILE="${HIHY_VERSION_STATUS_FILE:-$HIHY_ROOT_DIR/result/version-check.state}"
HIHY_VERSION_CHECK_LOCK_FILE="${HIHY_VERSION_CHECK_LOCK_FILE:-$HIHY_ROOT_DIR/result/version-check.lock}"
HIHY_VERSION_CHECK_TTL="${HIHY_VERSION_CHECK_TTL:-21600}"
HIHY_REMOTE_CONNECT_TIMEOUT="${HIHY_REMOTE_CONNECT_TIMEOUT:-2}"
HIHY_REMOTE_MAX_TIME="${HIHY_REMOTE_MAX_TIME:-5}"
HIHY_YQ_VERSION="${HIHY_YQ_VERSION:-v4.44.3}"
HIHY_YQ_BASE_URL="${HIHY_YQ_BASE_URL:-https://github.com/mikefarah/yq/releases/download}"

