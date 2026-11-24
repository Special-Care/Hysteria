#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/hy2.sh"

# Replay the redirects observed after the upstream repository moved.
curl() {
    local follow=false arg
    for arg in "$@"; do
        case "$arg" in
            --location|-[^-]*L*) follow=true ;;
        esac
    done
    printf 'HTTP/2 301\r\nlocation: https://github.com/HyNetworks/hysteria/releases/latest\r\n\r\n'
    if "$follow"; then
        printf 'HTTP/2 302\r\nLocation: https://github.com/HyNetworks/hysteria/releases/tag/app/v2.14.0\r\n\r\nHTTP/2 200\r\n'
    fi
}
[[ "$(getLatestHysteriaVersion)" == app/v2.14.0 ]]

curl() { printf 'HTTP/2 200\r\n'; }
if getLatestHysteriaVersion; then
    echo 'Expected missing release tag to fail' >&2
    exit 1
fi
echo 'Hysteria release checks passed.'
