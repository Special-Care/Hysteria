# ---------------------------------------------------------------------------
# sing-box core management (multi-protocol foundation)
#
# sing-box serves VLESS/VMess/Trojan (later plans). Releases ship a per-arch
# tar.gz (no checksums file), so this mirrors downloadHysteriaCore: HTTPS
# download + non-empty/runnable check, plus a tar extraction. The version is
# pinned for reproducible configs; override via HIHY_SINGBOX_VERSION.
# ---------------------------------------------------------------------------
HIHY_SINGBOX_VERSION="${HIHY_SINGBOX_VERSION:-v1.13.14}"
HIHY_SINGBOX_BASE_URL="${HIHY_SINGBOX_BASE_URL:-https://github.com/SagerNet/sing-box/releases/download}"
HIHY_SINGBOX_BIN="${HIHY_SINGBOX_BIN:-$HIHY_ROOT_DIR/bin/sing-box}"

getSingboxArch() {
    # Maps `uname -m` (or $1) to a sing-box release arch token.
    local machine="${1:-$(uname -m)}"
    case "$machine" in
        x86_64|amd64)        printf 'amd64' ;;
        aarch64|arm64)       printf 'arm64' ;;
        armv7l|armv7|armhf)  printf 'armv7' ;;
        i686|i386)           printf '386' ;;
        s390x)               printf 's390x' ;;
        ppc64le)             printf 'ppc64le' ;;
        loongarch64|loong64) printf 'loong64' ;;
        *) return 1 ;;
    esac
}

getLatestSingboxVersion() {
    local headers
    headers=$(fetchRemoteHeadersFromSources "https://github.com/SagerNet/sing-box/releases/latest") || return 1
    printf '%s\n' "$headers" | grep -i '^location:' | grep -o 'tag/[^[:space:]]*' | sed 's/tag\///;s/\r//;s/ //g' | head -n 1
}

downloadSingboxCore() {
    local version="$HIHY_SINGBOX_VERSION"
    local arch
    if ! arch=$(getSingboxArch); then
        echoColor red "Error[OS Message]: 不支持的架构 $(uname -m),无法下载 sing-box"
        return 1
    fi

    local ver_no_v="${version#v}"
    local dir_name="sing-box-${ver_no_v}-linux-${arch}"
    local file_name="${dir_name}.tar.gz"
    local url="${HIHY_SINGBOX_BASE_URL%/}/${version}/${file_name}"

    echoColor purple "正在下载 sing-box ${version} (${arch})..."

    local tmp_tar tmp_dir
    tmp_tar=$(mktemp) || return 1
    tmp_dir=$(mktemp -d) || { rm -f "$tmp_tar"; return 1; }

    if ! downloadToFile "$url" "$tmp_tar" || [ ! -s "$tmp_tar" ]; then
        rm -rf "$tmp_tar" "$tmp_dir"
        echoColor red "下载 sing-box 失败:网络错误或返回内容为空"
        return 1
    fi

    if ! tar -xzf "$tmp_tar" -C "$tmp_dir" >/dev/null 2>&1; then
        rm -rf "$tmp_tar" "$tmp_dir"
        echoColor red "解压 sing-box 失败"
        return 1
    fi

    local extracted="$tmp_dir/${dir_name}/sing-box"
    if [ ! -f "$extracted" ]; then
        rm -rf "$tmp_tar" "$tmp_dir"
        echoColor red "sing-box 压缩包结构异常,未找到二进制"
        return 1
    fi

    mkdir -p "$(dirname "$HIHY_SINGBOX_BIN")"
    if ! chmod +x "$extracted" || ! mv "$extracted" "$HIHY_SINGBOX_BIN"; then
        rm -rf "$tmp_tar" "$tmp_dir"
        echoColor red "sing-box 安装失败"
        return 1
    fi
    rm -rf "$tmp_tar" "$tmp_dir"

    if [ ! -s "$HIHY_SINGBOX_BIN" ]; then
        echoColor red "sing-box 安装失败"
        return 1
    fi
    echoColor green "sing-box 已安装到 ${HIHY_SINGBOX_BIN}"
    return 0
}
