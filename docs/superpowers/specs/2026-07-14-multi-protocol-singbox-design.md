# 多协议安装设计(sing-box + hysteria 双核)

- 日期:2026-07-14
- 分支:`feature/feature_multi-protocol`
- 目标文件:`server/hy2.sh`(单文件分发器)、`server/install.sh`、测试脚本、`md/` 文档

## 1. 概述

把 `hihy` 从"只装 Hysteria2"扩展为**多协议安装器**:安装时选择一种协议,一台机器只跑一种协议(重装即覆盖)。新增协议 **VLESS(REALITY)/ VMess / Trojan**,由 `sing-box` 核心提供;现有 **Hysteria2** 继续由 `apernet/hysteria` 核心提供,代码路径基本不动。

### 非目标(明确排除)

- **不支持 SSR**(已废弃、有安全弱点、无现代核心支持)。
- **不支持 SS/Shadowsocks**(用户明确要求去掉)。
- **不支持多协议并存**(一机一协议)。
- 不做全量参数暴露(采用"最佳实践默认 + 关键可选项")。

## 2. 已确定的关键决策

| # | 决策 | 说明 |
|---|---|---|
| D1 | **双核架构** | `apernet/hysteria`(hy2)+ `sing-box`(vmess/vless/trojan) |
| D2 | 协议清单 | hy2、vless、vmess、trojan(去掉 ss/ssr) |
| D3 | 一机一协议 | 单活协议,重装即覆盖,沿用现有单实例模型 |
| D4 | vless 默认 | REALITY + Vision(`xtls-rprx-vision`)+ TCP |
| D5 | 可配置度 | 最佳实践默认 + 关键可选项(端口、传输、证书/REALITY、拥塞控制、凭证)|
| D6 | 拥塞控制统一 | 三选项 `1.Brutal(默认) 2.Reno(更稳) 3.BBR(更快)` 出现在**每个**协议,按核心映射到不同底层机制(见 §5)|
| D7 | 老用户无感 | hy2 走现有路径,升级脚本后装法不变;新协议为增量 |

### 拥塞控制能力事实(核实结论)

- **Hysteria2 / apernet 核心**:原生支持 Brutal / BBR(三档 profile)/ **Reno**。保持现状。
- **sing-box hysteria2**:只支持 Brutal / BBR(`bbr_profile`),**无 Reno** —— 这是选双核而非纯 sing-box 的直接原因。
- **sing-box TCP 协议(vmess/vless/trojan)**:
  - Brutal → `multiplex.brutal`(需 `tcp-brutal` 内核模块,sing-box ≥1.7.0,且客户端也要开 mux+brutal 才生效)。
  - Reno / BBR → **Linux 内核 sysctl** `net.ipv4.tcp_congestion_control`(所有内核自带 reno;bbr 需 4.9+)。核心本身不实现,内核实现。

## 3. 架构:双核 + 单活协议

### 目录结构

```
/etc/hihy/
  bin/
    appS          # apernet/hysteria 核心(仅 hy2,现有)
    sing-box      # sing-box 核心(vmess/vless/trojan,新增)
    yq  jq        # yq 现有;jq 新增(sing-box JSON 增量编辑用)
  conf/
    config.yaml   # hy2 配置(现有,不动)
    config.json   # sing-box 配置(新增)
    backup.yaml   # 安装参数备份(现有,扩展 protocol/core 等字段)
  active          # 新增:当前活跃协议/核心状态文件
  cert/ result/ logs/ acl/   # 现有,复用
```

### `active` 状态文件

纯 key=value,例如:

```
protocol=vless
core=sing-box
transport=tcp-reality
congestion=brutal
```

- `core ∈ {hysteria, sing-box}`,`protocol ∈ {hysteria2, vless, vmess, trojan}`。
- **所有生命周期命令开头读该文件并分派**到对应核心实现。
- 读取封装成 `getActiveCore` / `getActiveProtocol`,路径经 `HIHY_ACTIVE_FILE`(默认 `/etc/hihy/active`)可覆盖,保持可测。

## 4. 安装流程 & 每协议可配置项

`install()` 最前面新增**协议选择**(在 `classifyInstallState` / `recoverPartialInstallState` 之后、核心下载之前):

```
请选择要安装的协议:
  1、Hysteria2 (默认, QUIC)
  2、VLESS   (REALITY 抗封锁)
  3、VMess
  4、Trojan
```

- 选 1 → 现有 `downloadHysteriaCore` + `setHysteriaConfig`(基本不动)。
- 选 2/3/4 → 新增 `downloadSingboxCore` + `setSingboxConfig <protocol>`。

### 各协议"关键可配置项"

**通用(vmess/vless/trojan 都问):** 备注 remarks、**端口**、传输/安全方式、拥塞控制、凭证(默认自动生成,可自定义)。**端口任意可输**。

**VLESS**(默认 REALITY+Vision+TCP)
- 端口(默认 `443`)
- 传输/安全:`1.TCP+REALITY(默认) 2.WS+TLS 3.gRPC+TLS`
- REALITY 时:借用 SNI 网站(默认 `www.microsoft.com`),自动生成 `reality` keypair(`sing-box generate reality-keypair`)+ `short_id`;`flow=xtls-rprx-vision`(仅 TCP+REALITY)
- TLS 时:走共用 `acquireCert`(ACME/本地/自签/DNS)+ 域名
- 拥塞控制:Brutal/Reno/BBR
- UUID:自动(`sing-box generate uuid`),可自定义

**VMess**(默认 WS+TLS)
- 端口(默认随机高位端口)
- 传输/安全:`1.WS+TLS(默认) 2.TCP 3.gRPC+TLS`
- WS path:默认随机(如 `/<8位随机>`)
- TLS 时:`acquireCert` + 域名
- 拥塞控制;UUID 自动(`alterId=0`)

**Trojan**(默认 TCP+TLS)
- 端口(默认 `443`)
- 传输/安全:`1.TCP+TLS(默认) 2.WS+TLS 3.gRPC+TLS`
- 证书:`acquireCert`(TLS 必需)+ 域名
- 拥塞控制;密码自动生成,可自定义

**Hysteria2**:现有 13 步流程原样保留,不改。

## 5. 拥塞控制统一模型

共用菜单函数 `chooseCongestion` 输出 `congestion ∈ {brutal,reno,bbr}`(+ Brutal 的带宽/延迟,+ BBR profile),再按核心分派:

| 用户选 | hy2(apernet 核心,不变) | vmess/vless/trojan(sing-box) |
|---|---|---|
| **Brutal** | 填上下行带宽+延迟 → `bandwidth`(现有) | inbound `multiplex:{enabled,padding, brutal:{enabled,up_mbps,down_mbps}}`(同样问带宽);**自动装 `tcp-brutal` 内核模块**;失败(OpenVZ/LXC/无内核头)→ 回退 BBR + 警告;客户端配置自动带 mux+brutal |
| **Reno** | `congestion.type=reno`(现有) | 内核 sysctl:`net.ipv4.tcp_congestion_control=reno`,写 `/etc/sysctl.d/99-hihy.conf` |
| **BBR** | `congestion.type=bbr` + `bbrProfile`(现有,三档) | 内核 sysctl:`=bbr` + `net.core.default_qdisc=fq`,写 `/etc/sysctl.d/99-hihy.conf` |

- Hysteria2 保留三选项原样(含 Reno)。
- sysctl 文件由脚本创建、`sysctl --system` 生效,卸载时删除并复原。
- Brutal 回退逻辑:探测 `modprobe brutal` / DKMS 安装结果;失败即把 `active` 的 `congestion` 记为 `bbr` 并继续。

## 6. 共用模块复用

- **`acquireCert`(重构提取)**:从现有 `setHysteriaConfig` 抽出 ACME/本地/自签/DNS 四种取证逻辑为独立函数,供 trojan、TLS 版 vmess/vless 复用。**只抽取、不改行为**;hy2 改为调用它。这是本次唯一需要动现有 hy2 代码的改动点。
- **`chooseCongestion`**:见 §5。
- **ACL 分流(菜单12)**:sing-box 协议 → 写 `route.rules`;hy2 → 现有 `acl.txt`。按核心分派。
- **socks5 出站 / warp(菜单15)**:sing-box → 写 `outbounds` + `route`;hy2 → 现有。按核心分派。
- **流量统计(菜单13)**:sing-box → 启用 Clash API(`experimental.clash_api`)读取;hy2 → 现有 hysteria traffic API。按核心分派。

## 7. sing-box 配置生成

- 生成方式:**heredoc 模板 + 变量替换**产出 `config.json`(不依赖 jq 生成);增量编辑(ACL/socks5)用 `jq`。
- 通用骨架:`log` + `inbounds[单个]` + `outbounds[direct(+socks5)]` + 可选 `route` + 可选 `experimental.clash_api`。
- 每协议 inbound 关键字段:
  - **vless**:`type=vless`,`users[{uuid,flow?}]`,`tls{enabled,server_name,reality{enabled,handshake{server,port},private_key,short_id}}` 或普通 `tls{acme/自备证书}`;可选 `transport{type=ws|grpc,...}`;可选 `multiplex.brutal`。
  - **vmess**:`type=vmess`,`users[{uuid,alterId:0}]`,`tls{...}`,`transport{type=ws,path}` 等;可选 `multiplex.brutal`。
  - **trojan**:`type=trojan`,`users[{password}]`,`tls{...}`(必需),`transport?`;可选 `multiplex.brutal`。
- `sing-box check -c config.json` 在启动前做校验;失败则报错并保留 `install-failed` marker。

## 8. 生命周期命令 & 菜单/分发器改造

所有命令开头 `core=$(getActiveCore)` 分派。菜单编号保持不变(遵守 CLAUDE.md:新特性接入 `case` 分发器 + `show_menu`)。

| 菜单 | 改造 |
|---|---|
| 1 安装 | 协议选择,分派 hy2 / sing-box |
| 3/4/5/6 启停/状态 | 读 `active`;sing-box 服务命令 `sing-box run -c /etc/hihy/conf/config.json` |
| 7 更新Core | 更新当前活跃核心(hysteria 或 sing-box) |
| 8 查看配置 | 按协议生成分享链接 + 二维码 + Clash.Meta / sing-box 客户端配置 |
| 9 重新配置 | 重跑当前协议配置流程 |
| 12 ACL / 13 统计 / 15 socks5 | 按核心分派(§6) |
| 2 卸载 | 清理两核产物 + sysctl 文件 + tcp-brutal 痕迹 |

- 服务脚本(OpenRC / systemd 复用现有 start/stop 函数 / rc.local)按核心生成不同 `command`/`command_args`。端口跳跃、allow-port 等 rc.local 脚本仅 hy2 需要。
- 菜单标题措辞改中文"安装(多协议)"等,保持中文。

## 9. 客户端输出(菜单8)

每协议生成:
- 标准分享链接:`vless://` / `vmess://`(base64 JSON)/ `trojan://` / `hysteria2://`(现有)
- 二维码(复用现有 `generate_qr`)
- Clash.Meta yaml(扩展现有 `generateMetaYaml` 支持四协议)
- sing-box 客户端 json(新增,便于 sing-box 客户端直接导入)

## 10. 核心管理

- **sing-box 下载**:`SagerNet/sing-box` releases,架构映射 amd64/arm64/armv7/386/s390x/ppc64le/loong64;沿用 `downloadToFile` + 版本检查(`getLatestSingboxVersion`)。
- **jq**:缺失时按现有 `installPinnedYq` 套路装 pinned `jq` 到 `bin/jq`,变量 `HIHY_JQ_BIN` 可覆盖。
- **tcp-brutal**:仅 TCP 协议选 Brutal 时安装(官方 `tcp.hy2.sh` 或 DKMS,需内核头);失败回退 BBR。

## 11. 安装状态恢复 / 卸载 / 迁移

- `classifyInstallState` 的 `owned_paths` 增加:`bin/sing-box`、`conf/config.json`、`active`。`has_core_assets` 判定同时覆盖两核。
- `recoverPartialInstallState` / `uninstall` 同步清理:`sing-box`、`config.json`、`active`、`/etc/sysctl.d/99-hihy.conf`(并 `sysctl --system` 复原)、tcp-brutal 配置。
- **迁移**:双核使 hy2 现有安装完全不受影响;新协议为增量,无需数据迁移。

## 12. 测试

- 扩展 `server/test_bootstrap_install.sh` / `server/test_install_recovery.sh`(sourcing 生产脚本 + `HIHY_*` 重定向 + `MOCK_BIN` 假命令的现有模式)。
- 新增覆盖:sing-box 下载 mock、`sing-box` 版本/生成命令 mock、协议选择分派、各协议 `config.json` 生成、`active` 状态读写、含 sing-box 产物的 `classifyInstallState` / 恢复、sysctl 文件的写入与清理。
- 新增可覆盖变量:`HIHY_SINGBOX_BIN`、`HIHY_JQ_BIN`、`HIHY_ACTIVE_FILE`、`HIHY_SYSCTL_FILE`。

## 13. 发布注意(遵守 CLAUDE.md)

- `hihyV` 版本常量随发布同步 bump(`server/hy2.sh` 顶部 + `show_menu` + `README.md` 头 + `md/logs.md`)。
- 远程 URL(`install.sh`、自更新、后台版本检查)指向 `main`,改动需先推 `main` 用户才可见。
- 新增 sing-box 相关文档到 `md/`(中文),README 更新协议清单。

## 14. 分阶段实施建议(供 writing-plans 拆解)

1. **地基**:`active` 状态模型 + `getActiveCore/Protocol` + 命令分派骨架;sing-box 下载/版本/jq;安装状态恢复扩展。
2. **抽取 `acquireCert`**(hy2 改调用,行为不变,测试保绿)。
3. **Trojan**(最简单:TCP+TLS,直接复用 `acquireCert`)端到端:配置生成 → 服务 → 客户端输出 → 测试。确立 sing-box 协议的实现范式。
4. **VLESS + REALITY**(keypair/short_id/vision)。
5. **VMess**(WS+TLS 默认)。
6. **拥塞控制统一**:`chooseCongestion` + TCP Brutal(内核模块+回退)+ sysctl BBR/Reno,套用到三协议。
7. **共用能力分派**:ACL / socks5 / 流量统计的 sing-box 分支。
8. **菜单/文档/版本**收尾。

## 15. 未决 / 风险

- **TCP Brutal 客户端依赖**:仅当客户端也开 mux+brutal 才生效;非 sing-box/不支持 mux 的客户端用不上 Brutal(退化为普通 TCP)。已通过"自动装模块+失败回退 BBR+客户端配置自动带 mux"缓解,并在安装时提示。
- **REALITY 借用站可达性**:默认 `www.microsoft.com`,允许用户改;需 TLS1.3+H2 的站点。
- **sing-box 版本兼容**:multiplex/brutal 需 ≥1.7.0;下载时选稳定版并校验。
