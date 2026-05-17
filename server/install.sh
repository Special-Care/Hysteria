#!/bin/bash
HIHY_BIN_LINK="${HIHY_BIN_LINK:-/usr/bin/hihy}"
HIHY_HYSTERIA2_URL="${HIHY_HYSTERIA2_URL:-https://raw.githubusercontent.com/Special-Care/Hysteria/refs/heads/main/server/hy2.sh}"

downloadHihyScript() {
    local url="$1"
    local output_path="${2:-$HIHY_BIN_LINK}"
    local output_dir
    local temp_output_path
    local output_name

    output_dir="$(dirname "$output_path")"
    output_name="$(basename "$output_path")"
    mkdir -p "$output_dir" || return 1
    temp_output_path="$(mktemp "$output_dir/.${output_name}.tmp.XXXXXX")" || return 1

    if command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$temp_output_path" "$url" || {
            rm -f "$temp_output_path"
            return 1
        }
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$temp_output_path" "$url" || {
            rm -f "$temp_output_path"
            return 1
        }
    else
        echo -e "\033[31m未找到 curl 或 wget，无法下载 hihy，请先安装其中之一后重试\033[0m" >&2
        return 1
    fi

    chmod +x "$temp_output_path" && mv "$temp_output_path" "$output_path" || {
        rm -f "$temp_output_path"
        return 1
    }
}

main() {
    echo -e "Downloading hihy..."

    if ! downloadHihyScript "$HIHY_HYSTERIA2_URL" "$HIHY_BIN_LINK"; then
        exit 1
    fi

    if ! "$HIHY_BIN_LINK"; then
        echo -e "\033[31mhihy 启动失败，请检查下载结果或稍后重试\033[0m" >&2
        exit 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
