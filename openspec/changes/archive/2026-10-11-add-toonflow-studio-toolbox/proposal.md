## Why

AI 短视频工坊在「剧本 → 分镜 → 生成」链路上已有完整实现，但缺乏一套经过大规模实战验证的导演规则层与画布化制作环境。Toonflow（HBAI-Ltd/Toonflow-app，MIT）是一个成熟的 AI 短剧/漫剧平台，其 `packages/skills/workflow/SKILL.md`（1406 行 PART A 规则书）覆盖了剧情保真、时长预算、站位自包含、表演通道、跨段连续性与生成稳定性预检，并有 8 个画布节点插件、9 个 Agent 工具、Docker 一体化部署。

把 Toonflow 以「本机 Docker 服务 + 资产互通」的形式接入工具箱，让用户在同一个桌面环境里既保留工坊的本地数据与交付链路，又能使用 Toonflow 的画布与规则书完成更专业的漫剧制作。参照本仓库既有的 `artex-engine` 能力先例（容器化外部引擎的托管范式），本变更引入第二个「容器托管 + 门户集成」工具。

## What Changes

- **新增「Toonflow 漫剧工坊」工具**（`toonflow-studio`），以嵌入式页面（非独立窗口）提供：
  - Docker Compose 工程定位与校验（工程目录必须含 `Dockerfile` 与 `compose.yaml`）
  - 守护进程探活、宿主机端口预检、`up -d`、健康就绪探测、`stop`，以及就绪超时时的容器日志附挂
  - 镜像构建入口（流式日志 + 已知失败模式分类为可操作提示）
  - 就绪后「打开工作台」入口（`http://127.0.0.1:<port>`），以及 Docker Desktop 跳转
  - 数据位置说明卡片（明确哪些数据不在本软件数据目录内、备份时需一并考虑）
- **运行时配置以 Docker Compose override 注入**，而非修改上游 `compose.yaml`：
  - 宿主机端口映射（默认 3177，避开 ARTEX 的 8787/8788 与本机常见占用）
  - **数据目录改为宿主机 bind mount**（`AppPaths.toonflowDataDir` → 容器 `/app/data`），替代上游的命名卷，使资产桥可直接文件系统读写
  - 容器内用户与宿主机 uid/gid 对齐（容器默认用户 `bun` 非 root）
- **资产桥（V8 工坊 ↔ Toonflow 工作区）**：
  - 导出：把剧集的粗剧情大纲、世界观、角色卡（含基准参考图）、场景卡（含主视图）写入 `toonflow_data/workspaces/<series-id>/` 下的画布 JSON 与 `assets/<nodeId>/`，供 Toonflow 画布与 Agent 直接使用
  - 导回：扫描工作区 `assets/` 下新产生的视频产物，按生成时间与命名归集到工坊当前集的 `segments/` 或 `clips/`
  - 桥**只写内容节点与素材文件**，不写画布的连线与生成状态；连线与生成由用户在 Toonflow 内通过 Agent 完成
- **密钥边界**：Toonflow 的 `data/settings.json` 以明文保存供应商 API Key（`conf` 包行为，`configFileMode: 0o600`）。本工具**绝不读写** `settings.json`，也不把该文件的任何内容纳入本软件的日志、导出或诊断输出。
- **非目标**：不实现 Toonflow 的 UI 复刻或内嵌 WebView（沿用 `artex-engine` 的「SHALL NOT embed or replicate the engine's Web interface」先例）；不在本变更内移植 PART A 规则书到 Dart 侧（属于工坊自身的改造）；不引入 Toonflow 的 MCP 或 A2A 接入。

## Capabilities

### New Capabilities

- `toonflow-studio`: 定义本软件如何托管容器化的 Toonflow 平台——Compose 工程定位、容器启停与状态呈现、健康就绪判定、端口分配与冲突预检、override 注入（含 bind mount 与用户对齐）、镜像构建与失败诊断、应用退出时的容器处置。
- `toonflow-asset-bridge`: 定义 V8 工坊与 Toonflow 工作区之间的资产导出与导回契约——导出的内容范围与落盘结构、导回的扫描与归集规则、密钥边界（不触碰 `settings.json`）、以及写画布内容的权限边界。

### Modified Capabilities

- `app-shell`: 工具栏新增一个 `ai` 分类下的工具入口与独立窗口之外的嵌入式页面形态；工具 id 进入最近使用与代理通道键空间。
- `settings-storage`: 新增工具级配置键 `toonflow-studio`（工程目录、端口、退出时是否停止容器、构建参数）与一个新的数据目录登记项。

## Impact

- **新增代码**：`lib/tools/toonflow_studio/{models,services,ui}/`
  - `models/toonflow_studio_config.dart`（不可变配置 + 宽容 `fromJson`）
  - `models/toonflow_studio_state.dart`（`enum Status` + `enum FailureKind` + 不可变状态快照）
  - `services/process_runner.dart`（可注入的进程执行抽象，测试用假实现）
  - `services/toonflow_compose_service.dart`（启停、健康探测、override 生成）
  - `services/toonflow_image_build_service.dart`（流式构建 + 失败模式分类）
  - `services/toonflow_asset_bridge.dart`（导出/导回）
  - `services/toonflow_config_store.dart`（`SettingsStore` 薄封装）
  - `ui/toonflow_studio_page.dart`
- **修改**：
  - `lib/tools/tool_definition.dart`：新增 `kToolIdToonflowStudio`
  - `lib/tools/registry.dart`：新增 `ToonflowStudioToolDefinition` 并注册
  - `lib/services/app_paths.dart`：新增 `toonflowDir`、`toonflowDataDir` 并登记进 `allDirs`
  - `test/app_paths_test.dart`、`test/frequently_used_tools_test.dart`：同步断言
- **外部依赖**：本机 Docker（含 Compose v2）、Toonflow 源码仓库（`~/Workspace/github/Toonflow-app`，用户已具备）、约 3–6GB 磁盘用于镜像与数据。
- **不引入新的 pubspec 依赖**：进程经 `Process.start`、HTTP 经既有 `http`、打开浏览器经 `Process.run('open')`——与 `artex-engine` 一致。
- **新增文档**：`docs/toonflow_studio.md`（运行前提、架构、bind mount 与 uid/gid 说明、数据位置、密钥边界、端口、构建失败诊断、退出时行为）。
