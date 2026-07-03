# hihy-remote-install Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个 agent 无关的 skill:通过 GNU screen 持久 SSH 会话在远程 Linux 服务器上执行 hihy 的 Hysteria2 安装,安装中的 13 步交互问答实时转发给用户逐题回答。

**Architecture:** 核心能力在纯 bash 会话驱动脚本 `hihy-session.sh`(screen 后台会话 + hardcopy 读屏 + stuff 送输入,无需 sshpass);`SKILL.md` 是 agent 无关的操作手册;仓库根 `AGENTS.md` 提供 Codex 等 agent 的发现入口。

**Tech Stack:** Bash、GNU screen、OpenSSH。测试为独立 bash 脚本(无框架,mktemp 隔离,mock 交互脚本),与仓库现有 `server/test_*.sh` 同风格。

**Spec:** `docs/superpowers/specs/2026-07-03-hihy-remote-install-skill-design.md`

## Global Constraints

- 用户可见文本用中文,注释与标识符用英文(与仓库约定一致)。
- 所有可配置路径/名称走 `${HIHY_X:-default}` 环境变量覆盖模式,保证可测试性。
- 不引入 sshpass、tmux、expect 等新依赖;只用 screen + ssh(macOS/主流 Linux 自带 screen)。
- SKILL.md 正文不得出现任何特定 agent 的专属工具名(如 AskUserQuestion);提问表述为通用指令。
- 远端安装命令逐字使用 README 的两条 URL:
  主源 `bash <(curl -fsSL https://cdn.jsdelivr.net/gh/Special-Care/Hysteria@main/server/install.sh)`,
  备源 `bash <(curl -fsSL https://raw.githubusercontent.com/Special-Care/Hysteria/main/server/install.sh)`。
- 安装完成标志字符串逐字为:`安装成功,请查看下方配置详细信息`。
- 敏感值(ssh 密码、认证口令、DNS API token)只经 stdin 送入(`send-secret`),不进命令行参数。
- 不做:密钥登录参数化、多会话并发、13 步答案预设文件。
- 测试不得依赖真实服务器,不得在本机执行任何 hihy 安装动作。

---

### Task 1: hihy-session.sh 会话生命周期(start/status/stop)

**Files:**
- Create: `.claude/skills/hihy-remote-install/scripts/hihy-session.sh`
- Test: `.claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`

**Interfaces:**
- Consumes: 无(首任务)。
- Produces(后续任务依赖的调用约定):
  - `hihy-session.sh start <ip> <ssh_port> <user>` — 建立 screen 会话跑 ssh;`HIHY_SESSION_CMD` 非空时改跑该命令(测试钩子),此时可不传参数。成功打印 `session '<name>' started`,失败 exit 1。
  - `hihy-session.sh status` — 存活打印 `alive` exit 0;否则打印 `dead` exit 1。
  - `hihy-session.sh stop` — 结束会话、删除 `$HIHY_SESSION_DIR`,打印 `session '<name>' stopped`;会话不存在时也安全返回 0。
  - 环境变量:`HIHY_SESSION_NAME`(默认 `hihy-install`)、`HIHY_SESSION_DIR`(默认 `${TMPDIR:-/tmp}/hihy-session.<uid>`)、`HIHY_SESSION_CMD`(默认空)、`HIHY_SCROLLBACK`(默认 5000)。

- [ ] **Step 1: 写失败测试**

创建 `.claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`:

```bash
#!/bin/bash
# Standalone test for hihy-session.sh - no framework, mirrors server/test_*.sh style.
# Drives a local mock command through the screen-backed session driver; no real server.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SH="${SCRIPT_DIR}/hihy-session.sh"

TEST_ROOT="$(mktemp -d)"
export HIHY_SESSION_NAME="hihy-test-$$"
export HIHY_SESSION_DIR="${TEST_ROOT}/session"

PASS=0
FAIL=0

cleanup() {
    bash "$SESSION_SH" stop >/dev/null 2>&1
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

assert_contains() {
    # assert_contains <haystack> <needle> <label>
    if printf '%s' "$1" | grep -q "$2"; then
        pass "$3"
    else
        fail "$3"
        echo "---- got (last 20 lines) ----"
        printf '%s\n' "$1" | tail -20
        echo "-----------------------------"
    fi
}

test_lifecycle() {
    echo "=== test_lifecycle ==="
    export HIHY_SESSION_CMD="sleep 300"

    if bash "$SESSION_SH" start >/dev/null 2>&1; then
        pass "start creates session"
    else
        fail "start creates session"
        return
    fi

    assert_contains "$(bash "$SESSION_SH" status)" "alive" "status reports alive"

    # start again must replace the old session, not error out
    if bash "$SESSION_SH" start >/dev/null 2>&1; then
        pass "start is idempotent (replaces stale session)"
    else
        fail "start is idempotent (replaces stale session)"
    fi
    assert_contains "$(bash "$SESSION_SH" status)" "alive" "status alive after restart"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    sleep 1
    if bash "$SESSION_SH" status >/dev/null 2>&1; then
        fail "status exits non-zero after stop"
    else
        pass "status exits non-zero after stop"
    fi

    if bash "$SESSION_SH" stop >/dev/null 2>&1; then
        pass "stop is safe when session already gone"
    else
        fail "stop is safe when session already gone"
    fi

    unset HIHY_SESSION_CMD
}

test_lifecycle

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`
Expected: FAIL(`hihy-session.sh` 不存在,start 失败),脚本以非零退出。

- [ ] **Step 3: 写最小实现**

创建 `.claude/skills/hihy-remote-install/scripts/hihy-session.sh`:

```bash
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
```

然后 `chmod +x` 两个文件:

```bash
chmod +x .claude/skills/hihy-remote-install/scripts/hihy-session.sh \
         .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`
Expected: `test_lifecycle` 6 项全 PASS,`Results: 6 passed, 0 failed`,exit 0。

注:若沙箱环境下 screen 无法创建会话(权限报错),用绕过沙箱方式重跑;仍失败则检查 `screen -ls` 输出。

- [ ] **Step 5: 语法检查并提交**

```bash
bash -n .claude/skills/hihy-remote-install/scripts/hihy-session.sh
bash -n .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh
git add .claude/skills/hihy-remote-install/scripts/
git commit -m "Add screen-backed session driver lifecycle (start/status/stop)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: hihy-session.sh 输入输出(read/send/send-secret)+ 全流程 mock 测试

**Files:**
- Modify: `.claude/skills/hihy-remote-install/scripts/hihy-session.sh`(追加 3 个子命令)
- Modify: `.claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`(追加 mock 与 2 个测试)

**Interfaces:**
- Consumes: Task 1 的 `cmd_start`/`session_alive`/`die`/环境变量。
- Produces:
  - `hihy-session.sh read [N|all]` — 导出屏幕+回滚缓冲,打印最后 N 行(默认 120),`all` 打印全部;会话不存在时 exit 1。
  - `hihy-session.sh send <text>` — 送入一行文本并回车;`send ""` 表示只按回车(用户选默认值)。
  - `hihy-session.sh send-secret` — 从 stdin 读一行送入并回车;敏感值不进程序参数。

- [ ] **Step 1: 写失败测试**

在 `test_hihy_session.sh` 中、`test_lifecycle` 函数之后追加:

```bash
write_mock() {
    # Simulates the remote side: ssh password prompt -> shell -> hihy menu
    # -> first install question -> success marker. Sleeps keep the screen
    # session alive long enough for the test to read the final output.
    cat > "${TEST_ROOT}/mock_remote.sh" <<'MOCK'
#!/bin/bash
printf "root@203.0.113.10's password: "
IFS= read -r pw
if [ "$pw" != "s3cret" ]; then
    echo ""
    echo "Permission denied, please try again."
    sleep 10
    exit 1
fi
echo ""
echo "Welcome to mock server"
printf 'root@mock:~# '
IFS= read -r cmd
echo "Downloading hihy..."
echo "1、安装Hysteria2"
printf '请选择: '
IFS= read -r choice
if [ "$choice" != "1" ]; then
    echo "unexpected menu choice: $choice"
    sleep 10
    exit 1
fi
echo "(1/13)请选择证书申请方式:"
printf '输入序号: '
IFS= read -r cert
echo "cert choice: $cert"
echo "安装成功,请查看下方配置详细信息"
sleep 30
MOCK
    chmod +x "${TEST_ROOT}/mock_remote.sh"
}

wait_for() {
    # wait_for <grep_pattern> [timeout_s]  -> prints the read snapshot that matched
    local pattern="$1" timeout="${2:-15}" out="" i=0
    while [ "$i" -lt $((timeout * 2)) ]; do
        out="$(bash "$SESSION_SH" read 2>/dev/null)"
        if printf '%s' "$out" | grep -q "$pattern"; then
            printf '%s' "$out"
            return 0
        fi
        sleep 0.5
        i=$((i+1))
    done
    printf '%s' "$out"
    return 1
}

test_full_install_loop() {
    echo "=== test_full_install_loop ==="
    write_mock
    export HIHY_SESSION_CMD="bash ${TEST_ROOT}/mock_remote.sh"

    bash "$SESSION_SH" start >/dev/null 2>&1 || { fail "start with mock"; return; }
    pass "start with mock"

    out="$(wait_for "password:")" || true
    assert_contains "$out" "password:" "read surfaces password prompt"

    printf '%s\n' "s3cret" | bash "$SESSION_SH" send-secret
    out="$(wait_for "root@mock")" || true
    assert_contains "$out" "Welcome to mock server" "send-secret answers password prompt"

    bash "$SESSION_SH" send "bash install.sh"
    out="$(wait_for "请选择")" || true
    assert_contains "$out" "1、安装Hysteria2" "menu appears after install command"

    bash "$SESSION_SH" send "1"
    out="$(wait_for "(1/13)")" || true
    assert_contains "$out" "(1/13)请选择证书申请方式" "install step 1 prompt is readable"

    bash "$SESSION_SH" send "3"
    out="$(wait_for "安装成功")" || true
    assert_contains "$out" "安装成功,请查看下方配置详细信息" "success marker visible"

    out="$(bash "$SESSION_SH" read all)"
    assert_contains "$out" "Welcome to mock server" "read all keeps full history"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    unset HIHY_SESSION_CMD
}

test_wrong_password() {
    echo "=== test_wrong_password ==="
    write_mock
    export HIHY_SESSION_CMD="bash ${TEST_ROOT}/mock_remote.sh"

    bash "$SESSION_SH" start >/dev/null 2>&1 || { fail "start with mock (wrong pw)"; return; }
    wait_for "password:" >/dev/null || true

    printf '%s\n' "wrong-password" | bash "$SESSION_SH" send-secret
    out="$(wait_for "Permission denied")" || true
    assert_contains "$out" "Permission denied" "auth failure is detectable via read"

    bash "$SESSION_SH" stop >/dev/null 2>&1
    unset HIHY_SESSION_CMD
}
```

并把文件底部的调用区改为:

```bash
test_lifecycle
test_full_install_loop
test_wrong_password

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`
Expected: `test_lifecycle` 通过;`test_full_install_loop` 从 `read surfaces password prompt` 起 FAIL(`read`/`send`/`send-secret` 子命令还不存在,dispatcher 走 `usage` 分支),整体 exit 非零。

- [ ] **Step 3: 写最小实现**

在 `hihy-session.sh` 的 `cmd_status` 之前插入三个函数:

```bash
cmd_read() {
    local lines="${1:-120}"
    session_alive || die "session not running"
    rm -f "$hardcopy_file"
    screen -S "$HIHY_SESSION_NAME" -p 0 -X hardcopy -h "$hardcopy_file"
    # hardcopy is written asynchronously by the screen daemon
    local i=0
    while [ ! -f "$hardcopy_file" ] && [ "$i" -lt 20 ]; do
        sleep 0.1
        i=$((i+1))
    done
    [ -f "$hardcopy_file" ] || die "hardcopy failed (screen did not write dump file)"
    if [ "$lines" = "all" ]; then
        cat "$hardcopy_file"
    else
        tail -n "$lines" "$hardcopy_file"
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
```

dispatcher 的 `case` 中、`start)` 之后插入:

```bash
    read) shift; cmd_read "$@" ;;
    send) shift; cmd_send "$@" ;;
    send-secret) cmd_send_secret ;;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh`
Expected: 三个测试函数全部 PASS(共 14 项),`Results: 14 passed, 0 failed`,exit 0。

- [ ] **Step 5: 提交**

```bash
bash -n .claude/skills/hihy-remote-install/scripts/hihy-session.sh
git add .claude/skills/hihy-remote-install/scripts/
git commit -m "Add read/send/send-secret to session driver with mock install-loop test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: SKILL.md 操作手册

**Files:**
- Create: `.claude/skills/hihy-remote-install/SKILL.md`

**Interfaces:**
- Consumes: Task 1/2 的全部子命令约定(start/read/send/send-secret/status/stop)。
- Produces: agent 无关的完整操作流程文档,供任何 agent 执行远程安装时遵循。

- [ ] **Step 1: 写入 SKILL.md**

创建 `.claude/skills/hihy-remote-install/SKILL.md`,内容如下(逐字):

````markdown
---
name: hihy-remote-install
description: Install Hysteria2 (hihy) on a remote Linux server over SSH. Use when the user asks to remotely install or deploy hysteria2/hihy onto a server and provides (or can provide) server ip, ssh port, username and password. Drives the server-side 13-step interactive install by relaying each question to the user in real time through a screen-backed persistent SSH session.
---

# hihy 远程安装(实时问答转发)

本手册与任何具备 shell 执行能力的 agent 兼容(Claude Code、Codex 等)。
核心工具是本目录下的 `scripts/hihy-session.sh`:基于 GNU screen 的持久交互会话驱动,
**不需要 sshpass**(screen 提供伪终端,密码当作按键送入)。

下文 `$SKILL_DIR` 指本文件所在目录;`$SESSION` 指 `bash "$SKILL_DIR/scripts/hihy-session.sh"`。

## 前置条件

- 本机有 `screen` 与 `ssh`(macOS 与主流 Linux 自带)。
- 目标服务器:Linux,root 用户(或有 root 权限),开启密码登录。

## 会话脚本子命令

| 命令 | 作用 |
|---|---|
| `$SESSION start <ip> <ssh_port> <user>` | 建立会话并发起 ssh 连接 |
| `$SESSION read [N\|all]` | 打印远端屏幕+回滚的最后 N 行(默认 120) |
| `$SESSION send "<text>"` | 送入一行文本并回车;`send ""` 表示只按回车(选默认值) |
| `printf '%s\n' '<秘密>' \| $SESSION send-secret` | 敏感值经 stdin 送入,不进进程列表 |
| `$SESSION status` | 会话存活探测(alive/dead) |
| `$SESSION stop` | 结束会话并清理 |

## 操作流程

1. **收集连接信息**:向用户询问服务器 ip、ssh 端口(默认 22)、用户名(默认 root)、密码。
   有结构化提问工具就用,没有就纯文本逐项询问。
2. **登录**:`$SESSION start <ip> <port> <user>`,然后每 2-3 秒 `$SESSION read` 一次:
   - 出现 `password:` → 用 `send-secret` 送入密码;
   - 出现 `Permission denied` → 告知用户密码错误,重新要密码再 `send-secret`(3 次失败 ssh 会退出,
     此时 `stop` 后重新 `start`);
   - 出现 `Connection refused` / `Connection timed out` / `Could not resolve` → 告知用户连接失败原因,
     `stop` 清理后与用户核对 ip/端口;
   - 出现 shell 提示符(如 `root@…#`)→ 登录成功。
3. **启动安装**:送入 README 的线上安装命令:
   `$SESSION send "bash <(curl -fsSL https://cdn.jsdelivr.net/gh/Special-Care/Hysteria@main/server/install.sh)"`
   若 read 显示下载失败,改用备源:
   `$SESSION send "bash <(curl -fsSL https://raw.githubusercontent.com/Special-Care/Hysteria/main/server/install.sh)"`
4. **进入安装**:菜单出现(含 `1、安装Hysteria2` 与 `请选择:`)后 `$SESSION send "1"`。
5. **13 步问答实时转发**(核心循环):
   - `$SESSION read` 轮询(间隔 2-3 秒),对比上次快照找出**新出现的提示**
     (安装步骤形如 `(1/13)…` 到 `(13/13)…`,之间还可能有确认/子问题);
   - 把远端提示**原文**(含所有选项和默认值说明)转发给用户提问,不要替用户编造或省略选项;
   - 用户答"默认"/留空 → `$SESSION send ""`;其他答案原样 `send`;
   - 敏感输入(认证口令、DNS API token 等远端不回显的项)改用 `send-secret`;
   - 遇到长操作(下载 hysteria 内核、ACME 证书签发)没有新提示是正常的:继续轮询,最多等约
     120 秒;超时把当前屏幕内容展示给用户并询问是否继续等待。
6. **完成**:出现 `安装成功,请查看下方配置详细信息` 后,`$SESSION read all` 捕获完整输出,
   把客户端配置(分享链接、客户端 yaml 等)**完整**展示给用户。
7. **清理**:`$SESSION stop`。任何失败/中止路径都必须执行 `stop`,避免残留 screen 会话。

## 注意事项

- 密码经由对话与本地进程传递:建议用户使用临时密码,装完改密,或改用密钥登录后自行维护。
- 安装中途出错可直接重跑安装:hy2.sh 自带部分安装状态检测与自愈
  (`classifyInstallState` / `recoverPartialInstallState`)。
- 一次只维护一个安装会话;`start` 会自动替换同名残留会话。
- 本 skill 只做安装(菜单 1)。用户要卸载/改配置等,登录后送对应菜单序号即可,问答转发逻辑相同。
````

- [ ] **Step 2: 验证**

```bash
head -5 .claude/skills/hihy-remote-install/SKILL.md
grep -c "SESSION" .claude/skills/hihy-remote-install/SKILL.md
grep -n "AskUserQuestion\|Claude-only\|claude_code" .claude/skills/hihy-remote-install/SKILL.md || echo "OK: agent-agnostic"
```

Expected: frontmatter 前 5 行含 `name: hihy-remote-install`;第三条命令输出 `OK: agent-agnostic`(正文无 agent 专属工具名)。
人工核对:文中 6 个子命令名与 `hihy-session.sh` dispatcher 的 case 分支一一对应;两条安装 URL 与 README.md 一致;成功标志与 `server/hy2.sh:1930` 一致。

- [ ] **Step 3: 提交**

```bash
git add .claude/skills/hihy-remote-install/SKILL.md
git commit -m "Add agent-agnostic SKILL.md for remote Hysteria2 install

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: AGENTS.md 发现入口

**Files:**
- Create: `AGENTS.md`(仓库根)

**Interfaces:**
- Consumes: Task 3 的 SKILL.md 路径。
- Produces: Codex 等读 AGENTS.md 的 agent 对 skill 的发现入口。

- [ ] **Step 1: 写入 AGENTS.md**

创建仓库根 `AGENTS.md`,内容如下(逐字):

```markdown
# AGENTS.md

本仓库的通用开发指南见 [CLAUDE.md](CLAUDE.md)(内容适用于所有 agent,不只 Claude)。

## 可用技能(Skills)

### hihy-remote-install — 远程安装 Hysteria2

- **位置**:`.claude/skills/hihy-remote-install/SKILL.md`
- **触发**:用户要求把 Hysteria2/hihy 安装到某台远程服务器,并提供服务器 ip、ssh 端口、用户名、密码时。
- **用法**:完整阅读该 SKILL.md 并严格按其流程执行;核心会话工具为同目录的
  `scripts/hihy-session.sh`(基于 GNU screen,无需 sshpass)。安装中的 13 步交互问答必须
  实时转发给用户逐题回答,不得替用户编造答案。
```

- [ ] **Step 2: 验证**

```bash
grep -n "hihy-remote-install" AGENTS.md
test -f .claude/skills/hihy-remote-install/SKILL.md && echo "skill path valid"
```

Expected: 两行输出均非空,`skill path valid`。

- [ ] **Step 3: 提交**

```bash
git add AGENTS.md
git commit -m "Add AGENTS.md entry point for hihy-remote-install skill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 全量验证

**Files:**
- 无新文件;运行验证。

**Interfaces:**
- Consumes: 前四个任务的全部产物。
- Produces: 已验证的完整交付。

- [ ] **Step 1: 语法检查全部 bash 产物**

```bash
bash -n .claude/skills/hihy-remote-install/scripts/hihy-session.sh
bash -n .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh
```

Expected: 无输出,exit 0。

- [ ] **Step 2: 跑新测试 + 仓库既有测试(确认无回归)**

```bash
bash .claude/skills/hihy-remote-install/scripts/test_hihy_session.sh
bash server/test_bootstrap_install.sh
bash server/test_install_recovery.sh
```

Expected: 三个测试全部通过(新测试 `14 passed, 0 failed`;既有两个测试保持原有全 PASS 输出)。

- [ ] **Step 3: 残留检查**

```bash
screen -ls || true
```

Expected: 无 `hihy-test-*` 会话残留(测试的 trap cleanup 已清理)。

---

## Self-Review 记录

- **Spec 覆盖**:会话机制与 6 个子命令(Task 1/2)、SKILL.md 工作流+错误处理+安全注意(Task 3)、AGENTS.md(Task 4)、本地自测与语法检查(Task 1/2/5)——spec 各节均有对应任务。真实服务器端到端验证按 spec 属用户后续动作,不在本计划内。
- **占位符**:无 TBD/TODO;所有代码块完整可粘贴。
- **类型/命名一致性**:子命令名 `start/read/send/send-secret/status/stop` 在脚本 dispatcher、测试、SKILL.md、AGENTS.md 中一致;环境变量 `HIHY_SESSION_NAME/HIHY_SESSION_DIR/HIHY_SESSION_CMD/HIHY_SCROLLBACK` 一致;成功标志字符串与 `hy2.sh:1930` 逐字一致。
