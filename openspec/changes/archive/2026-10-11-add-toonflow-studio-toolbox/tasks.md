## 0. Spike：bind mount 与容器用户对齐（阻塞后续任务）

> Open Question 1 必须在写 override 之前有结论。这一组任务的产出是一个结论 + 一段最小可用的 override 草稿，不是产品代码。

- [x] 0.1 启动 Docker Desktop，确认 `docker info` 可达
- [x] 0.2 用上游 `compose.yaml` + 最小 override（bind mount `toonflow_data/` → `/app/data`，不带 `user:`）跑一次 `up -d`，在容器内 `touch /app/data/probe`，确认宿主机是否可见该文件
- [x] 0.3 若 0.2 不可写，改用 `user: "<uid>:<gid>"`（`id -u` / `id -g` 取值）重复 0.2
- [x] 0.4 若 `user:` 仍不生效，验证 `user: "0:0"` + 宿主机目录 `chmod 700` 是否满足「容器可写且目录不属其他用户」
- [x] 0.5 记录结论到 design.md 的 Open Question 1，并确定 override 的最终形态
- [x] 0.6 测出首次 `docker compose build` 的耗时与镜像体积，记录到 design.md 的 Open Question 2
- [x] 0.7 确认默认端口（候选 3177）在本机空闲，记录到 design.md 的 Open Question 3

## 1. 配置与数据路径

- [x] 1.1 `lib/services/app_paths.dart` 新增 `toonflowDir` 与 `toonflowDataDir`，两者登记进 `allDirs`；**不**把 `settings.json` 登记进 `allFiles`
- [x] 1.2 `models/toonflow_studio_config.dart`：不可变配置（`projectDir`、`httpPort`、`stopOnAppExit`、`bunRegistry`）+ 宽容 `fromJson`（端口接受 int 或 String、空串回退默认、`stopOnAppExit` 默认 true）
- [x] 1.3 `services/toonflow_config_store.dart`：`SettingsStore.readToolConfig/writeToolConfig('toonflow-studio')` 薄封装 + `locateProject`（区分「目录不存在」与「缺 `Dockerfile`/`compose.yaml`」）+ `setConfigForTesting`/`resetForTesting`
- [x] 1.4 更新 `test/app_paths_test.dart`：新增目录已登记、`settings.json` 未登记

## 2. 进程抽象与 Compose 生命周期

- [x] 2.1 `services/process_runner.dart`：`ProcessRunner` 抽象 + `RealProcessRunner`（30s 默认超时、`ProcessException` 转为失败结果不抛给 UI）+ `FakeProcessRunner`（`calls`/`script`/`callsTo`/`called`/`startStreaming`）
- [x] 2.2 `models/toonflow_studio_state.dart`：`enum Status { idle, starting, running, stopping, stopped, failed }` + `enum FailureKind { dockerUnavailable, projectNotFound, portConflict, healthTimeout, composeFailed, buildRequired, unknown }` + 不可变状态与 `isBusy`/`canOpenWorkspace` 派生
- [x] 2.3 `services/toonflow_override_store.dart`：override 生成（端口映射 + bind mount + 按 0.5 结论的用户对齐）、生成标记注释、非本工具文件先备份、`pathFor` 与测试用的 `decodeOverride`
- [x] 2.4 `services/toonflow_compose_service.dart`：`isDockerAvailable`（`docker info`）、`findConflictingPort`（`ServerSocket.bind` 探测）、`start()` 六步序列（定位 → 探活 → 端口预检 → override → `up -d` → 健康探测）、`stop()`、`disposeOnExit()`
- [x] 2.5 健康探测：`GET http://127.0.0.1:<port>/api/workspaces/list`，判据为 200 + JSON 对象含 `code` 字段；总预算与轮询间隔可注入（测试压缩）；HTML 响应判未就绪
- [x] 2.6 `toonflow_compose_service_test.dart`：`FakeProcessRunner` 驱动——工程缺失/端口冲突/守护进程不可达/**200+HTML 误就绪**/超时附容器日志/重复启动不二次 `up`

## 3. 镜像构建

- [x] 3.1 `services/toonflow_image_build_service.dart`：单飞（复用 in-flight Future）、流式日志（尾部缓冲上限 2000 行）、`BUN_CONFIG_REGISTRY` 注入、`docker compose -f <yml> -f <override> build`
- [x] 3.2 失败模式分类：守护进程不可达 / 镜像源 403 / 网络超时 / 锁文件不匹配 / 工程缺失，每类给出可操作 hint
- [x] 3.3 `toonflow_build_failure_test.dart`：用真实 docker 输出样本断言分类正确（样本来自 spike 或 docker 标准文案）

## 4. 工具页面

- [x] 4.1 `ui/toonflow_studio_page.dart`：`AnimatedBuilder` 监听 compose service + config store；布局为状态卡 → 配置卡 → 构建区 → 失败卡 → 日志查看器 → 数据位置卡 → 能力边界说明（后两块不可折叠，与 ARTEX 的 spec 要求同理）
- [x] 4.2 状态卡：状态徽章、工作台地址、「打开工作台」（未就绪禁用 + 阻塞原因）、「Docker Desktop」跳转、启动/停止开关
- [x] 4.3 配置卡：工程目录、端口、退出时是否停止容器、bun 镜像站；保存后即时生效并同步输入框
- [x] 4.4 数据位置卡：明确 `toonflow_data/` 位置、`settings.json` 的密钥边界声明、备份范围提示
- [x] 4.5 复用或新建日志查看器组件（构建日志 / 容器日志切换 + busy 态 + 空态提示）
- [x] 4.6 `toonflow_ui_contract_test.dart`：未就绪时「打开工作台」禁用、数据位置卡包含密钥边界声明、配置卡字段齐全

## 5. 资产桥

- [x] 5.1 `services/toonflow_asset_bridge.dart` 导出：读剧集/集的 `synopsis`、`worldview`、`styleTokens`、角色卡与场景卡（含参考图文件），生成确定性节点 id，写画布 JSON 与 `assets/<nodeId>/content.md`、参考图拷贝；`edges` 恒为空
- [x] 5.2 导出前确保 `toonflow_data/workspaces/` 存在；写文件用原子写（`.tmp` + rename）
- [x] 5.3 导回：扫描 `toonflow_data/workspaces/<series-id>/assets/` 下本次导出后新增/修改的视频文件，按 mtime 排序，用户勾选后**复制**到当前集 `segments/` 或 `clips/` 并按分镜顺序写回剧集数据
- [x] 5.4 未选中集时报告需要先选择目标集，不猜测
- [x] 5.5 密钥边界：桥不读写 `settings.json`；诊断与错误文本不含其内容
- [x] 5.6 `toonflow_asset_bridge_test.dart`：导出的画布 JSON 含 `toonflowCanvas: true` 且 `edges` 为空；`textPath` 与 `content.md` 一致；重复导出覆盖同名不建第二目录；**导出/归集后 `settings.json` 的 mtime 不变**；导回复制而非移动

## 6. 注册与接线

- [x] 6.1 `lib/tools/tool_definition.dart` 新增 `const kToolIdToonflowStudio = 'toonflow-studio'`
- [x] 6.2 `lib/tools/registry.dart` 新增 `ToonflowStudioToolDefinition`（`ai` 分类、嵌入式页面）并加入 `ToolRegistry.tools`
- [x] 6.3 `lib/main.dart` 的 `runShutdownCleanup()` 接入 `ToonflowComposeService.instance.disposeOnExit()`（守卫：失败仍退出）
- [x] 6.4 更新 `test/frequently_used_tools_test.dart` 的 `ai` 分类断言，加入 `'toonflow-studio'`

## 7. 文档与收尾

- [x] 7.1 `docs/toonflow_studio.md`：运行前提（Docker + Compose + 仓库路径 + 磁盘预估）、架构与职责切分、bind mount 与 uid/gid 说明（含 spike 结论）、数据位置表（明确 `settings.json` 不在本软件管理范围）、密钥边界、端口、构建失败诊断、退出时行为、许可边界（MIT）
- [x] 7.2 全量回归：`flutter test` 通过；`flutter analyze --no-fatal-infos` 无新增 error/warning
- [x] 7.3 手工验证：真实 docker 启动一次，确认 bind mount 可写、探测判就绪、导出的画布能被 Toonflow 工作台打开、导回的片段进入工坊当前集
- [x] 7.4 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh` 并确认部署实例正常运行
