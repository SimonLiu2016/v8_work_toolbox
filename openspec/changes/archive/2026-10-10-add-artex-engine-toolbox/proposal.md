## Why

现有「安全工具箱」（`lib/tools/security_toolbox/`，24,473 Dart 行）是一个 CLI 工具编排层：它自身几乎不实现任何检测能力，完全依赖 Homebrew 安装的 nmap / nuclei / sqlmap 等外部命令，AI 侧只有 286 行的 ReAct 循环（`maxIterations=3`）加 9~11 个预设工具。它缺少自主渗透平台的核心：planner/worker 分离的认知架构、跨任务共享的资产图与每任务独立的探索图、RoE 范围强制与四段权限管线、蜜罐识别、MITM 流量证据链、漏洞验证闭环。这些不是加几个工具能补上的，需要换一个引擎。

ARTEX（`/Users/simon/Workspace/github/artex-ymh`，AGPL-3.0）正是这样的引擎：Go 单体后端（109k 行）+ Next.js 前端（54.5k 行）+ PostgreSQL 双图架构，已通过 Docker Compose 完整容器化。本软件仅作者本机使用，无授权合规问题；容器边界同时把 AGPL 的传染链切断——本仓库新增代码是 MIT，不与 AGPL 代码发生链接或衍生。

已完成的 spike 验证（2026-10-10，全部通过）：镜像冷构建 9 分钟出 1.67GB 镜像；`/api/health` 返回 `{"ok":true,"service":"artex","version":"dev"}`；前端静态页 200/14.8KB；8788 流量代理带口令 200、无口令 407；容器内存占用 65MB。详见 `design.md` 的「Spike 结论」。

## What Changes

- **新增工具「ARTEX 渗透引擎」**（id `artex-engine`，`ToolCategory.security`）：一个 Docker Compose 生命周期管理器 + 浏览器入口，不实现任何渗透能力本身。
- **容器生命周期管理**：启停、健康探测（校验响应体而非仅 HTTP 状态码）、启动日志查看、退出时可选自动停止。
- **镜像构建入口**：把 `docker compose build` 包成一个按钮，并对四类高频失败模式给出可操作诊断（Docker 未启动 / 镜像源 403 / 网络超时 / `.env` 缺失），而非原样抛出构建输出。
- **`docker-compose.override.yml` 注入**：不改 artex 原仓库文件，由本工具生成并维护一份 override，承担两个职责——注入 `ARTEX_GATE=off`（否则容器内门控自动开启，`/api/health` 返回假 nginx 页面）、覆盖端口映射（端口可配置）。
- **端口可配置 + 冲突预检**：默认 8787/8788，启动前用 `ServerSocket.bind` 侦测；冲突时启动失败并说明具体原因，用户可改端口后重试。
- **根 CA 安装引导**：检测 `data/traffic/_ca/mitmproxy-ca-cert.pem` 是否存在，给出 `sudo security add-trusted-cert` 命令与一键复制；不自动执行（系统级副作用）。
- **能力边界明示**：UI 与文档明确说明内网隧道工具（chisel/suo5）镜像未预置，开箱可用范围是「外网自动化探索」，不含内网纵深。

## Capabilities

### New Capabilities

- `artex-engine`: 本软件对 ARTEX Docker 引擎的托管能力——容器与镜像生命周期、健康就绪判定、端口分配与冲突处理、构建失败诊断、根 CA 引导，以及打开引擎工作台的入口。

### Modified Capabilities

- `security`: 该 capability 现有 spec 仅覆盖 `security/agent-session-state` 一个子能力（Agent 多会话状态隔离）。本 change 不改其任何需求，只在 `specs/security/artex-engine/` 下新增子能力 spec，与既有子能力并列。
- `app-shell`: 工具列表新增一个条目。`frequently_used_tools_test.dart` 断言每个 `ToolCategory` 非空、部分分类成员精确匹配——`security` 分类新增工具不影响这些断言（`security` 分类已有安全工具箱），但需回归确认。

## Impact

**新增代码**（约 1,000 Dart 行，零新依赖）：

```
lib/tools/artex_engine/
  models/artex_engine_state.dart        容器状态机 + 配置模型
  services/artex_compose_service.dart   compose 生命周期、健康探测、端口预检、override 生成
  services/artex_ca_service.dart        根 CA 检测与安装命令生成
  services/artex_image_build_service.dart  镜像构建 + 失败模式诊断
  ui/artex_engine_page.dart             主页面
  ui/artex_log_viewer.dart              容器/构建日志
lib/tools/registry.dart                 +1 工具条目
lib/main.dart                           SIGTERM 清理挂载
lib/services/app_paths.dart             artexDir 登记（compose 目录发现缓存）
```

**外部依赖**：Docker Desktop（已安装，29.8.2）；artex 仓库本地副本（`~/Workspace/github/artex-ymh`，含本 change 打过的 `ARTEX_GATE` 补丁——但实现改用 override 机制，不再依赖修改原文件）。

**数据位置**：引擎全部数据（PostgreSQL 卷 `artex-ymh_pgdata`、绑定挂载 `./data`）位于 artex 仓库目录下的 Docker 命名卷与绑定挂载，**不属于 `AppPaths` 管辖范围**。本工具只在 `AppPaths.artexDir` 存自己的配置（compose 目录路径、端口、开关）。

**不在本次范围**：不复刻 artex 的任何 UI；不实现 Flutter 侧 API 客户端；不内嵌 Go 二进制；不触碰现有安全工具箱的代码（两个工具并存，由用户自行决定是否退役旧工具）。
