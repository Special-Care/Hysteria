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
