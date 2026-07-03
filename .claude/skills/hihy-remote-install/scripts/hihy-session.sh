#!/bin/bash
# hihy-session.sh - screen-backed persistent interactive session driver.
# Agent-agnostic: any shell-capable agent (Claude Code, Codex, a human) can
# drive a remote interactive install through these subcommands. No sshpass
# needed: screen provides the pty, so the ssh password prompt is answered
# with plain keystrokes via `send-secret`.
#
# Usage:
#   hihy-session.sh start <ip> <ssh_port> <user>
#   hihy-session.sh read [N|all]       # dump last N lines (default 120) of screen + scrollback
#   hihy-session.sh send <text>        # type one line + Enter
#   hihy-session.sh send-secret        # like send, but the line is read from stdin
#   hihy-session.sh status
#   hihy-session.sh stop

set -u

HIHY_SESSION_NAME="${HIHY_SESSION_NAME:-hihy-install}"
HIHY_SESSION_DIR="${HIHY_SESSION_DIR:-${TMPDIR:-/tmp}/hihy-session.$(id -u)}"
HIHY_SESSION_CMD="${HIHY_SESSION_CMD:-}"   # test hook: run this instead of ssh
HIHY_SCROLLBACK="${HIHY_SCROLLBACK:-5000}"

hardcopy_file="${HIHY_SESSION_DIR}/screen.dump"

die() { echo "hihy-session: $*" >&2; exit 1; }

session_alive() {
    screen -ls 2>/dev/null | grep -q "[.]${HIHY_SESSION_NAME}[[:space:]]"
}

cmd_start() {
    if [ -z "$HIHY_SESSION_CMD" ] && [ $# -lt 3 ]; then
        die "usage: start <ip> <ssh_port> <user>"
    fi
    if session_alive; then
        screen -S "$HIHY_SESSION_NAME" -X quit >/dev/null 2>&1
        sleep 1
    fi
    screen -wipe >/dev/null 2>&1
    mkdir -p "$HIHY_SESSION_DIR" || die "cannot create $HIHY_SESSION_DIR"
    chmod 700 "$HIHY_SESSION_DIR"
    if [ -n "$HIHY_SESSION_CMD" ]; then
        screen -h "$HIHY_SCROLLBACK" -dmS "$HIHY_SESSION_NAME" bash -c "$HIHY_SESSION_CMD"
    else
        local ip="$1" port="$2" user="$3"
        screen -h "$HIHY_SCROLLBACK" -dmS "$HIHY_SESSION_NAME" \
            ssh -o StrictHostKeyChecking=accept-new \
                -o ConnectTimeout=20 \
                -o NumberOfPasswordPrompts=3 \
                -p "$port" "${user}@${ip}"
    fi
    sleep 1
    session_alive || die "failed to start screen session"
    echo "session '${HIHY_SESSION_NAME}' started"
}

cmd_status() {
    if session_alive; then
        echo "alive"
    else
        echo "dead"
        return 1
    fi
}

cmd_stop() {
    if session_alive; then
        screen -S "$HIHY_SESSION_NAME" -X quit >/dev/null 2>&1
    fi
    screen -wipe >/dev/null 2>&1
    rm -rf "$HIHY_SESSION_DIR"
    echo "session '${HIHY_SESSION_NAME}' stopped"
}

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    status) cmd_status ;;
    stop) cmd_stop ;;
    *) die "usage: $0 {start|read|send|send-secret|status|stop}" ;;
esac
