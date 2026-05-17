# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`Hi Hysteria` (`hihy`) is a pure-Bash installer and manager for the [Hysteria2](https://github.com/apernet/hysteria) proxy server. It targets **root on Linux servers** (Alpine/OpenRC, Debian/Ubuntu, RHEL/CentOS/Alma/Rocky, Arch) across x86_64, arm64, armv7, i386, s390x, ppc64le. There is no build step, compiler, or package manager — only Bash plus runtime deps (`curl`/`wget`, `iptables`/`ufw`/`firewalld`, `openssl`, `yq`, the downloaded `hysteria` core binary).

User-facing strings and documentation under `md/` are in **Chinese**. Match that language when editing menu prompts, log messages, or `md/*.md` files; comments and identifiers stay in English.

## Layout

- `server/hy2.sh` — the monolithic manager script (~3600 lines). All install / uninstall / lifecycle / config / ACL / stats / log / socks5-outbound logic lives here. Installed to `/usr/bin/hihy`.
- `server/install.sh` — small bootstrap downloader. Fetches `hy2.sh` from `$HIHY_HYSTERIA2_URL` to `$HIHY_BIN_LINK`, then `exec`s it. This is what the README's `bash <(curl …)` one-liner runs.
- `server/test_bootstrap_install.sh`, `server/test_install_recovery.sh` — Bash test harnesses (see Testing).
- `md/` — Chinese user docs linked from `README.md` (firewall, certificate, masquerade, blacklist, speed, client, issues, logs).

## Testing

Both test scripts are standalone — no framework. Run them directly:

```bash
bash server/test_bootstrap_install.sh
bash server/test_install_recovery.sh
```

They work by **sourcing the production script** (so internal functions become callable in the test shell) and **redirecting all filesystem side effects via env-var overrides** (`HIHY_ROOT_DIR`, `HIHY_BIN_LINK`, `HIHY_YQ_BIN`, `HIHY_RC_LOCAL`, `HIHY_PID_FILE`, …) onto a `mktemp -d` root that gets cleaned up on exit. External commands (`curl`, etc.) are mocked by writing fakes into a `MOCK_BIN` directory and prepending it to `PATH`.

When adding new code that touches the filesystem or shells out, prefer reading paths from these `HIHY_*` variables (with the existing `${HIHY_X:-/default}` pattern) so it stays testable. A single test runs by calling the test function at the bottom of the file directly — there is no test selector flag.

This codebase is intended to **run on Linux production servers**, not the macOS dev environment. The tests are the only thing meant to execute locally; do not try to run `install`/`uninstall`/lifecycle commands on the dev machine.

## Architecture notes

**Single-file dispatcher.** `hy2.sh` is invoked either as the interactive menu (`menu` → `show_menu`) or with a subcommand argument that matches a menu number or a name: `install|1`, `uninstall|2`, `start|3`, `stop|4`, `restart|5`, `checkStatus|6`, `updateHysteriaCore|7`, `generate_client_config|8`, `changeServerConfig|9`, `changeIp64|10`, `hihyUpdate|11`, `aclControl|12`, `getHysteriaTrafic|13`, `checkLogs|14`, `addSocks5Outbound|15`, plus the internal `cronTask`. New top-level features need to be wired into the case statement at the bottom of `hy2.sh` **and** into `show_menu` / `menu`.

**Install-state recovery.** `classifyInstallState` returns `installed` / `partially-installed` / `not-installed` by inspecting owned artifacts under `$HIHY_ROOT_DIR` (default `/etc/hihy/`), the launcher symlink, the service scripts, and a `markInstallFailed`-written failure marker. `install()` always calls this first and runs `recoverPartialInstallState` to clean orphaned files before re-installing. Any new install-time artifact should be added to the `owned_paths` list in `classifyInstallState` and to the cleanup paths in `recoverPartialInstallState` / `uninstall` so half-failed installs can self-heal.

**Per-init-system service scripts.** `install()` writes a different service file depending on the distro (OpenRC on Alpine via `/etc/init.d/hihy`, otherwise the `start`/`stop`/`restart`/`status` functions defined later in the same file are reused through other init flows). Port-hopping and `allow-port` are separate scriptlets registered into `$HIHY_RC_LOCAL` (`/etc/rc.local`) via `setup_rc_local_for_arch` / `uninstall_rc_local_for_arch`.

**Firewall abstraction.** `allowPort` / `delHihyFirewallPort` detect `ufw` / `firewalld` / raw `iptables` and dispatch accordingly. Port-hopping uses **range** syntax that differs per backend (`47000:48000` for UFW/firewalld/iptables, `47000-48000` for the hysteria `listen` field). Always convert between the two forms when crossing the boundary — see `formatFirewallPortSpec` and the recent fix described in `md/logs.md` for `ver1.04-c`.

**Self-update.** `hy2.sh` updates itself in-place by downloading `$HIHY_REMOTE_SCRIPT_URL` (with `$HIHY_REMOTE_SCRIPT_MIRROR_URL` as fallback) and rewriting the launcher at `$HIHY_BIN_LINK`. A background version check (`startBackgroundVersionCheck`) writes timestamped state under `$HIHY_ROOT_DIR/result/version-check.state` with a TTL (default 6h) and a lock file to dedupe concurrent runs.

## Version constant

`hihyV` at the top of `server/hy2.sh` is the displayed version (currently `ver1.04-c`). It also appears in `show_menu`, the `README.md` header, and `md/logs.md`. Bump all three together on release.

## Remote URLs

`server/install.sh` (`$HIHY_HYSTERIA2_URL`) and `server/hy2.sh` (`$HIHY_REMOTE_SCRIPT_URL` + jsDelivr mirror `$HIHY_REMOTE_SCRIPT_MIRROR_URL`) hard-code download URLs that point at this repo's `main` branch (`Special-Care/Hysteria`). The bootstrap installer, the in-script self-update flow, and the background version checker all hit these — so a change must be pushed to `main` before users see it.
