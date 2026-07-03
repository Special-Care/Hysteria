#!/bin/bash
# hihy-session.sh - screen-backed persistent interactive session driver.
# Agent-agnostic: any shell-capable agent (Claude Code, Codex, a human) can
# drive a remote interactive install through these subcommands. No sshpass
# needed: screen provides the pty, so the ssh password prompt is answered
# with plain keystrokes via `send-secret`.
#
# Usage:
#   hihy-session.sh start <ip> <ssh_port> <user>
#   hihy-session.sh read [N|all]       # print last N lines (default 120) of the raw pty log; `all` = whole log
#   hihy-session.sh send <text>        # type one line + Enter
#   hihy-session.sh send-secret        # like send, but the line is read from stdin
#   hihy-session.sh status
#   hihy-session.sh stop

set -u

HIHY_SESSION_NAME="${HIHY_SESSION_NAME:-hihy-install}"
HIHY_SESSION_DIR="${HIHY_SESSION_DIR:-${TMPDIR:-/tmp}/hihy-session.$(id -u)}"
HIHY_SESSION_CMD="${HIHY_SESSION_CMD:-}"   # test hook: run this instead of ssh
HIHY_SCROLLBACK="${HIHY_SCROLLBACK:-5000}"
# HIHY_SCROLLBACK bounds only screen's own in-memory scrollback buffer. `read`
# tails the raw -L log on disk (see log_file below), which grows unbounded, so
# `read all` output is NOT limited by HIHY_SCROLLBACK.

log_file="${HIHY_SESSION_DIR}/screenlog.0"

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
    # screen opens its -L logfile in append mode, so a leftover file from a
    # previous session would bleed into this one's `read` output.
    rm -f "$log_file"
    # -L (+cd into HIHY_SESSION_DIR) makes screen tee the raw pty byte stream
    # to "$HIHY_SESSION_DIR/screenlog.0" == $log_file. `read` tails that
    # file instead of using `screen ... hardcopy`: this build of screen (the
    # ancient 4.00.03 macOS ships as /usr/bin/screen) silently truncates
    # multi-byte CJK codepoints to their low byte in the hardcopy character
    # grid, which corrupts hihy's Chinese menu text. The raw log is written
    # before that grid conversion, so it round-trips CJK text intact.
    if [ -n "$HIHY_SESSION_CMD" ]; then
        ( cd "$HIHY_SESSION_DIR" && screen -L -h "$HIHY_SCROLLBACK" -dmS "$HIHY_SESSION_NAME" bash -c "$HIHY_SESSION_CMD" )
    else
        local ip="$1" port="$2" user="$3"
        ( cd "$HIHY_SESSION_DIR" && screen -L -h "$HIHY_SCROLLBACK" -dmS "$HIHY_SESSION_NAME" \
            ssh -o StrictHostKeyChecking=accept-new \
                -o ConnectTimeout=20 \
                -o NumberOfPasswordPrompts=3 \
                -p "$port" "${user}@${ip}" )
    fi
    sleep 1
    session_alive || die "failed to start screen session"
    # This screen build flushes its -L logfile on a fixed ~10s timer for the
    # very first write of a session, regardless of the "flush" value below;
    # every write after that first flush lands on disk within well under a
    # second. So the one caller-visible cost is a ~10s wait before the very
    # first `read` after `start` sees anything - callers with a poll loop
    # (see wait_for() in the test) should budget >10s for that first read.
    screen -S "$HIHY_SESSION_NAME" -X logfile flush 0 >/dev/null 2>&1
    echo "session '${HIHY_SESSION_NAME}' started"
}

clean_terminal_noise() {
    # Strip terminal control noise from the raw pty log before it reaches the
    # caller. hy2.sh writes all interactive text through echoColor, wrapping it
    # in CSI/SGR colour sequences (\033[32m ... \033[0m, \033[1;33;40m, ...),
    # and its countdown() animates with echo -ne "N\b \b", leaving interleaved
    # digits and bare backspaces in the log. Left in, these corrupt what `read`
    # surfaces and break line-oriented grepping by callers.
    #   1. drop CSI/SGR escape sequences (colours, cursor ops)
    #   2. drop bare backspace (\b, 0x08) and carriage return (\r, 0x0d)
    # This only rewrites the bytes printed to the caller; the log file itself is
    # never modified.
    local esc
    esc=$(printf '\033')
    sed "s/${esc}\[[0-9;?]*[a-zA-Z]//g" | tr -d '\010\015'
}

cmd_read() {
    local lines="${1:-120}"
    session_alive || die "session not running"
    # $log_file is screen's own -L logfile (see cmd_start); nothing to
    # trigger here. A live session whose log file is still absent is the
    # normal transient before screen's first flush (see cmd_start) - the
    # session just started and nothing has hit disk yet - so return empty,
    # distinct from a missing session (handled above with die/exit 1).
    if [ ! -f "$log_file" ]; then
        return 0
    fi
    if [ "$lines" = "all" ]; then
        clean_terminal_noise < "$log_file"
    else
        tail -n "$lines" "$log_file" | clean_terminal_noise
    fi
}

stuff_line() {
    # screen's `stuff` interprets C-style backslash escapes; double them so
    # the remote side receives the answer byte-for-byte.
    local text="${1//\\/\\\\}"
    screen -S "$HIHY_SESSION_NAME" -p 0 -X stuff "${text}"$'\r'
}

cmd_send() {
    [ $# -ge 1 ] || die "usage: send <text>"
    session_alive || die "session not running"
    stuff_line "$1"
}

cmd_send_secret() {
    session_alive || die "session not running"
    local secret
    IFS= read -r secret || die "no secret on stdin"
    stuff_line "$secret"
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
    read) shift; cmd_read "$@" ;;
    send) shift; cmd_send "$@" ;;
    send-secret) cmd_send_secret ;;
    status) cmd_status ;;
    stop) cmd_stop ;;
    *) die "usage: $0 {start|read|send|send-secret|status|stop}" ;;
esac
