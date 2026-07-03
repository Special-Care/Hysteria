# AGENTS.md

本仓库的通用开发指南见 [CLAUDE.md](CLAUDE.md)(内容适用于所有 agent,不只 Claude)。

## 可用技能(Skills)

### hihy-remote-install — 远程安装 Hysteria2

- **位置**:`.claude/skills/hihy-remote-install/SKILL.md`
- **触发**:用户要求把 Hysteria2/hihy 安装到某台远程服务器,并提供服务器 ip、ssh 端口、用户名、密码时。
- **用法**:完整阅读该 SKILL.md 并严格按其流程执行;核心会话工具为同目录的
  `scripts/hihy-session.sh`(基于 GNU screen,无需 sshpass)。安装中的 13 步交互问答必须
  实时转发给用户逐题回答,不得替用户编造答案。
