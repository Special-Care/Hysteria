# hihy-remote-install Skill 设计文档

日期:2026-07-03
状态:已确认

## 目标

提供一个 agent 无关的 skill:用户给出服务器 ip、ssh 端口、登录 user/password,由 agent 通过 SSH
连接到目标 Linux 服务器,执行 README.md 中的线上安装命令完成 Hysteria2(hihy)安装。
安装过程中服务器端的 13 步交互式问答**实时转发**给用户逐题回答,答案由 agent 回送到远端。

## 关键决策(与用户确认)

1. **交互处理**:13 步问答实时转发给用户逐题回答,不预先收集安装参数。
2. **脚本来源**:使用 README.md 的线上安装命令
   `bash <(curl -fsSL https://cdn.jsdelivr.net/gh/Special-Care/Hysteria@main/server/install.sh)`,
   jsDelivr 失败时回退 GitHub raw 源。
3. **跨 agent 可用**:不只 Claude Code,Codex 等其他 agent 也要能用。核心能力放在纯 bash
   辅助脚本中,SKILL.md 写成 agent 无关的操作手册,并通过 AGENTS.md 提供发现入口。

## 架构

### 会话机制:GNU screen(选定方案)

- `screen -dmS <session> ssh -p <port> <user>@<ip>` 建立分离式持久会话。
- screen 提供伪终端,ssh 的密码提示可直接用 `screen -X stuff` 送入 —— **不需要 sshpass**。
- 会话跨 agent 的多次 shell 调用持久存在;macOS 自带 screen,Linux 发行版普遍可装。
- 读输出:`screen -X hardcopy <file>` 导出当前屏幕;送输入:`screen -X stuff "<text>\n"`。

否决的备选:
- FIFO + 后台 ssh:ssh 密码从控制终端(/dev/tty)读取而非 stdin,后台无 TTY 时密码认证失败,
  需再套 expect,更脆弱。
- 每答一题重连:安装进度在远端进程中,断开即丢,不可行。

### 组件

```
.claude/skills/hihy-remote-install/
├── SKILL.md                    # agent 无关的操作手册(中文正文,英文标识符)
└── scripts/
    └── hihy-session.sh         # 纯 bash 会话驱动脚本,零 agent 依赖
AGENTS.md                       # 仓库根,指向 skill,供 Codex 等发现
```

### hihy-session.sh 子命令接口

| 子命令 | 行为 |
|---|---|
| `start <ip> <ssh_port> <user>` | 建立 screen 会话并发起 ssh 连接(密码随后经 `send` 送入,不上命令行参数) |
| `read` | hardcopy 导出当前远端屏幕内容到 stdout |
| `send <text>` | 送入一行输入并回车(用于密码、菜单选项、13 步答案) |
| `send-secret` | 从 stdin 读取一行送入(密码等敏感值不进程序参数/进程列表) |
| `status` | 报告会话是否存活 |
| `stop` | 结束远端 shell 并清理 screen 会话 |

实现要点:
- 会话名固定(如 `hihy-install`),重复 `start` 前先清理同名残留会话。
- `start` 使用 `ssh -o StrictHostKeyChecking=accept-new` 避免首次连接的 host key 交互卡死。
- hardcopy 输出为覆盖式快照;agent 通过对比前后快照识别新出现的提示。

### Agent 工作流(SKILL.md 正文描述)

1. 向用户收集 ip、ssh 端口(默认 22)、用户名(默认 root)、密码。
2. `start` 建会话 → `read` 轮询直到出现密码提示 → `send-secret` 送密码 → 确认登录成功
   (出现 shell 提示符;识别 Permission denied 则报告认证失败)。
3. 送入 README 线上安装命令;若 jsDelivr 源失败,改用 GitHub raw 源重试。
4. 菜单出现后 `send 1` 进入安装。
5. 循环:`read` → 发现新提示(如 `(N/13)` 步骤文本)→ 将**远端提示原文**转发给用户
   (有结构化提问工具则用,否则纯文本提问)→ 得到答案 → `send`。
   直到出现安装完成标志(hy2.sh 输出 `安装成功,请查看下方配置详细信息`)。
6. 捕获并向用户完整展示客户端配置输出(分享链接、客户端 yaml)。
7. `stop` 清理会话;任何失败路径同样执行 `stop`。

### 轮询节奏

`read` 之间等待 2-3 秒;远端长操作(下载核心二进制、ACME 签发)最长等待约 120 秒,
超时则把当前屏幕内容展示给用户并询问是否继续等待。

## 错误处理

- **连接失败/认证失败**:`read` 识别 `Connection refused` / `Permission denied` / 超时,
  报告用户并 `stop` 清理。
- **下载失败**:jsDelivr 源失败自动改用 GitHub raw 源;两者都失败则报告网络问题。
- **安装中途出错**:hy2.sh 自带 `classifyInstallState`/`recoverPartialInstallState` 自愈,
  重新运行安装即可;skill 文档注明这一点。
- **会话残留**:`start` 前和所有退出路径都清理同名 screen 会话。

## 安全注意(SKILL.md 中注明)

- 密码经由聊天与本地进程传递,建议用户使用临时密码或改用密钥登录。
- 密码通过 `send-secret`(stdin)送入,不出现在命令行参数与进程列表中。
- 远端脚本对认证口令等敏感输入本身使用 `read -rs` 不回显。

## 测试

- `hihy-session.sh` 语法检查(`bash -n`)。
- 本地自测:用 screen 会话驱动一个本地交互式 bash(或 mock 脚本)验证
  start/read/send/send-secret/status/stop 全链路,不需要真实服务器,
  与仓库现有测试同风格(独立 bash 脚本,mktemp 隔离)。
- 真实服务器端到端验证由用户在有测试机时进行。

## 不做的事(YAGNI)

- 不支持密钥登录参数化(用户明确要 user/password;密钥用户可自行 ssh)。
- 不做多会话并发安装。
- 不把 13 步答案做成配置文件预设(用户明确要实时逐题)。
