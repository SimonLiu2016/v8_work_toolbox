## Why

Toonflow 官方工作台在真实使用中「一点都不好用」，且它的 docker 形态要求本地维护一份 checkout（`Dockerfile` + `compose.yaml`）、首次构建 13.5 分钟、还要伺候 bun 镜像站。无限画布（[infinite-canvas](https://github.com/SimonLiu2016/infinite-canvas)，同为用户自有的 MIT 项目）同样支持 docker 部署，但**默认直接拉 `ghcr.io` 双架构镜像**，无本地构建门槛。

但换镜像不是换 `image:` 一行的事。Toonflow 是一个有服务端数据目录的真后端，本工具的资产桥整条建立在 bind mount 上；无限画布的 docker 容器只是 nginx 静态服务器，**密钥、画布、素材、生成记录全在浏览器的 IndexedDB**，文件系统上一个字节都没有。因此：

- bind mount / 数据目录 / 「绝不碰 settings.json」的密钥边界 —— 前提消失
- `画布1.json` + `toonflowCanvas` 标记 + `textPath` 的写盘契约 —— 无限画布只认 ZIP 导入
- 扫 `assets/*.mp4` 归集 —— 视频在 IndexedDB 的 Blob 里，扫不到任何东西
- `GET /api/workspaces/list` 要 JSON 信封的健康探针 —— 无限画布没有任何业务 API，nginx 对任意路径都返回 200 HTML，**判据必须反过来**

结论：Docker 生命周期部分可以改造沿用，资产桥必须重造。本变更同时把「Toonflow」这个名字从代码、配置键、路径、spec 目录与文档中全部移除——留着是个骗人的名字。

## What Changes

**移除（Toonflow 全部）**

- **BREAKING**：删除 `lib/tools/toonflow_studio/` 整个目录，以及 `test/tools/toonflow_studio/` 下 7 个测试文件。
- **BREAKING**：删除 `AppPaths.toonflowDir` 与 `AppPaths.toonflowDataDir` 及 `ensureDirs` 登记——无限画布没有数据目录可挂。
- **BREAKING**：删除 `docs/toonflow_studio.md`、`openspec/specs/toonflow-studio/`、`openspec/specs/toonflow-asset-bridge/` 两个 spec 目录。
- **BREAKING**：`main.dart` 的退出处置改为调用新工具的同名方法。

**新增（无限画布工具）**

- 新工具 `infinite-canvas`（工具 id 从 `toonflow-studio` 改为 `infinite-canvas`，显示标题「无限画布」）。
- Compose 工程定位改为同时接受 `compose.yaml` / `compose.yml` / `docker-compose.yml`，默认路径 `~/Workspace/github/infinite-canvas`。
- 健康就绪判据反转：`GET /` 要求 200 且 body 含 `<div id="root">` 与 `/config.js` script 标签——后者由容器 entrypoint 生成，能同时证明「是这个容器的 nginx」且「entrypoint 已执行」。就绪预算从 60 秒大幅下调（静态服务是毫秒级，60 秒的理由原本是 Toonflow 的插件初始化）。
- override 只做两件事：把上游 `"3000:3000"`（绑全部网卡）覆盖成 `127.0.0.1` 回环，以及覆盖 `image:`。**删除 `user:` 对齐与 bind mount**——nginx 不写盘。
- 端口预检成为真安全需求：上游默认对局域网开放。
- 镜像入口降级：默认路径改为「拉 ghcr 镜像」；本地 `docker compose build` 保留为二级入口，仅在用户要用本地代码改动时才需要。构建失败分类表里 Toonflow 特有的 bun 锁文件条目删除。
- 打开工作台、退出停容器、失败分类（Docker 未运行 / 端口冲突 / 镜像未拉取 / 服务名不匹配）照搬。

**新增（loopback 资产桥）**

- V8 起一个只听 `127.0.0.1` 的 HTTP 服务（沿用 `LocalDictionaryBridge` 的 `HttpServer` 范式），提供两个职责：
  1. 签发画布节点插件 JS——URL 形如 `http://127.0.0.1:<port>/canvas-plugin.js`，用户在无限画布「按 URL 安装插件」一次后持久化在浏览器里；
  2. 提供 REST 端点供插件回传：视频生成结果（Blob base64 + 结构化元数据）、节点选取、就绪握手。
- 插件使用上游公开的 TypeScript SDK（`CanvasPlugin` / `CanvasPluginAi` / `applyOps`），可在画布上创建文本节点、图片节点、视频节点，并可调用宿主已配置渠道的 `ai.generateVideo`——**密钥全程不离开浏览器**。
- 导出方向：剧集世界观/风格词/剧本/分镜表 → 文本节点；角色卡与场景卡（含基准参考图）→ 图片节点 + 参考图。
- 导回方向：插件把视频节点的产物（`storageKey` → Blob）推到 V8，附带分镜号/片段 id 元数据，V8 复制到 `segments/` 或 `clips/` 并按分镜顺序写回剧集数据。**复制而非移动**（用户可能仍在画布里用它）。

**新增（密钥边界换对象）**

无限画布的配置文件 `infinite-canvas-config.json` 明文含 API Key 与 WebDAV 密码（上游文档原话「不应公开分享」）。本工具 SHALL 显式拒绝把它当作导入源，诊断日志 SHALL NOT 打印其内容。这条替代原「不碰 `toonflow_data/settings.json`」的边界，且新边界更危险——用户很可能顺手把配置文件一起丢进目录。

## Capabilities

### New Capabilities

- `infinite-canvas-studio`: Docker 托管的无限画布工作台生命周期管理——Compose 工程定位、容器启停、健康就绪判定（反转后的判据）、端口分配与冲突预检、override 注入（仅回环 + 镜像覆盖）、镜像入口与失败诊断、工作台入口、退出时容器处置。本工具不实现任何无限画布创作能力。
- `infinite-canvas-bridge`: V8 与无限画布之间的资产互传契约——loopback HTTP 服务、画布节点插件的签发与安装、导出的内容范围与落点、导回的推送与归集、密钥边界（拒绝配置文件）、以及写画布内容的权限边界。

### Modified Capabilities

- `frequently-used-tools`: 常用工具清单中 `toonflow-studio` 条目替换为 `infinite-canvas`。

## Impact

**删除**

- `lib/tools/toonflow_studio/`（11 文件，3231 行）与 `test/tools/toonflow_studio/`（7 文件，1589 行）。
- `lib/services/app_paths.dart`：`toonflowDir` / `toonflowDataDir` 两个 getter 与 `ensureDirs` 登记；`test/app_paths_test.dart` 对应断言。
- `openspec/specs/toonflow-studio/spec.md`、`openspec/specs/toonflow-asset-bridge/spec.md`、`docs/toonflow_studio.md`。

**新增**

- `lib/tools/infinite_canvas/`：`models/`（config、state）、`services/`（compose、image build、override、config store、bridge server、canvas plugin source、asset bridge）、`ui/`（studio page、bridge panel、log viewer）。
- `lib/main.dart`：退出处置调用点。
- `lib/tools/registry.dart`、`lib/tools/tool_definition.dart`：工具注册与 id 常量。
- `test/tools/infinite_canvas/`：对应测试。
- `test/frequently_used_tools_test.dart`：id 断言。
- `docs/infinite_canvas.md`：新文档。

**依赖**

- 无新增第三方依赖。HTTP 服务用 `dart:io` 的 `HttpServer`；ZIP 用已有的 `package:archive`（如需保留文件接力作为兜底路径）。

**上游风险**

- 插件依赖无限画布的 TypeScript SDK（`CanvasPlugin` / `CanvasPluginAi` / `CanvasNodeDefinition`）。上游 `git pull` 导致 SDK 漂移时，插件会加载失败——需在插件内做版本声明（`minAppVersion`）并在 V8 侧给出可读诊断。
- 上游 `compose.yaml` 的服务名（当前 `app`）改名时，override 会静默失效——沿用原工具的「服务名不匹配」失败分类。
