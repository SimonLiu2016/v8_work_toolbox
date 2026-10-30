## 1. 新工具骨架（spec: infinite-canvas-studio Compose 工程定位）

- [x] 1.1 建 `lib/tools/infinite_canvas/` 目录结构与 `models/infinite_canvas_config.dart`：字段为 `projectDir`（默认 `~/Workspace/github/infinite-canvas`）、`httpPort`（默认 3177）、`bridgePort`（默认 8798）、`stopOnAppExit`（默认 true）。删除 `bunRegistry` 与 `autoStartOnOpen`（design D12：默认关闭且无人用的开关不留）。全部字段有默认值——配置缺失或损坏时工具必须还能打开
- [x] 1.2 `models/infinite_canvas_config.dart` 的 `fromJson` 宽容类型（端口可能被手写成字符串），`toJson` 只写这 4 个键
- [x] 1.3 `models/infinite_canvas_state.dart`：`InfiniteCanvasStatus` 与 `InfiniteCanvasFailureKind` 枚举照搬原状态机的语义，失败类别表删掉 Toonflow 构建专属项、保留 `buildRequired`（改为「镜像未拉取」语义）
- [x] 1.4 `services/infinite_canvas_config_store.dart`：薄封装 `SettingsStore`，配置键 `infinite-canvas`；`locateProject` 探测 `compose.yaml` / `compose.yml` / `docker-compose.yml` 三种文件名并返回实际命中的那个（design D6）
- [x] 1.5 测试：配置缺省/损坏回落默认；三种 compose 文件名各自命中；目录不存在与缺 `Dockerfile` 分别给出不同失败原因（15 项全绿）

## 2. Compose 生命周期（spec: infinite-canvas-studio 容器启停 / 健康判定 / 端口预检）

- [x] 2.1 `services/process_runner.dart`：从旧工具原样搬（`ProcessRunner` 抽象 + 真实实现 + `InfiniteCanvasFakeProcessRunner`），改类名
- [x] 2.2 `services/infinite_canvas_override_store.dart`：override 只含 `image:` 覆盖与回环 `ports: !override`，服务名常量 `app`；文件名 `docker-compose.v8box.yml`（design D6 不复用隐式加载名）；标记注释首行 + 非托管文件先备份
- [x] 2.3 override 的 YAML 引号处理照搬旧实现的踩坑结论：整条卷/端口字符串加引号，引号不包一半（compose v5 go-yaml 会报 `did not find expected '-' indicator`）
- [x] 2.4 `services/infinite_canvas_compose_service.dart`：守护进程探活 → 端口预检 → 写 override → `up -d` → 健康探测 → 就绪/失败；失败分类含 Docker 未运行、端口冲突、服务名不匹配、镜像未拉取
- [x] 2.5 健康探针判据反转（design D5）：200 且 body 同时含 `<div id="root">` 与指向 `/config.js` 的 script 标签；就绪预算降到 15 秒，轮询间隔保持 1 秒
- [x] 2.6 `classifyHealthBody` 拆成可单测的静态方法；测试覆盖四类：真就绪、200 但是别的服务、有挂载点无 config.js、超时
- [x] 2.7 端口预检覆盖两个端口：工作台端口与资产桥端口（design D10），冲突时报端口号并允许改端口重试
- [x] 2.8 `stop()` 与 `disposeOnExit()`：失败必须上报而不是假装已停止；退出时停止失败不阻塞退出
- [x] 2.9 测试：启动成功路径的完整调用序列（docker info → 端口 bind → override 写 → up -d → 健康就绪）；端口冲突时**不调** docker；HTML 响应判未就绪；重复启动被忽略；stop 失败上报（22 项全绿）

## 3. 镜像入口（spec: infinite-canvas-studio 镜像入口与失败诊断）

- [x] 3.1 `services/infinite_canvas_image_build_service.dart`：`docker compose build` 单飞 + 流式日志 + 尾部缓冲（上限 2000 行）
- [x] 3.2 失败分类表重写：删 bun 锁文件条目，新增「构建上下文缺失」；保留镜像源 403、网络超时、Docker 未运行；顺序上具体特征排在宽泛网络特征之前
- [x] 3.3 启动路径默认不要求构建——`up -d` 时 compose 自己拉 ghcr 镜像；「镜像未拉取」失败分类匹配 `Unable to find image` / `pull access denied` / `manifest unknown`
- [x] 3.4 测试：分类函数对四类输入各归其位；构建期间重复触发复用同一次 Future，不产生两个并发 build（16 项全绿）

## 4. 资产桥 loopback 服务（spec: infinite-canvas-bridge 传输通道 / 密钥边界）

- [x] 4.1 `services/infinite_canvas_bridge_server.dart`：`dart:io` `HttpServer.bind(loopbackIPv4, port)`，复用 `LocalDictionaryBridge` 的响应头与 fail-soft 范式；端口冲突报可读原因
- [x] 4.2 安装时生成共享密钥，请求头校验，不匹配直接拒且不做任何查询；密钥写进签发的插件源码，不进浏览器存储之外的地方（design Risks 第五条）
- [x] 4.3 `/assets/*` 路由：把工坊的参考图原图按路径吐出，带 `Access-Control-Allow-Origin`（design D2）；范围限制在剧集目录内，拒绝 `..` 穿越
- [x] 4.4 `GET /api/episodes`：剧集 + 集列表，供插件面板选集
- [x] 4.5 `GET /api/export?seriesId&episodeId`：渲染导出载荷（design D3 的 JSON 形状），图片节点给 loopback URL 而非 base64（design D2）
- [x] 4.6 `POST /api/import`：收视频请求体原样落盘，流式写 `.part` 再 rename；超限在请求头阶段就拒（上限 512 MB）
- [x] 4.7 显式拒绝无限画布配置文件：任何把 `infinite-canvas-config.json` 递进来的路径都返回可读拒绝原因；诊断日志不打印其内容（design D8）
- [x] 4.8 测试：密钥不匹配被拒且不触达查询；`/assets/*` 拒路径穿越；导出载荷里不含任何 base64 图片数据、URL 指向 loopback；导入落盘后文件完整；配置文件被显式拒绝

## 5. 导出逻辑（spec: infinite-canvas-bridge 导出内容范围 / 节点可辨识性）

- [x] 5.1 `services/infinite_canvas_asset_bridge.dart` 的导出分支：世界观+风格词 → 文本节点、本集大纲+分镜表 → 文本节点、角色卡（中文外貌 + 英文正负向 Prompt + 基准参考图）→ 图片节点、场景卡 → 图片节点；从旧桥的 `_renderWorldview` / `_renderScript` 照搬渲染逻辑
- [x] 5.2 节点 id 由 `sha1(seriesId:episodeId:kind:localId)` 派生（照搬旧桥 `_nodeId`），重复导出幂等
- [x] 5.3 布局建议由 V8 给列数/间距，不再把所有节点堆在 `{x:0,y:0}`（design D3）
- [x] 5.4 角色无参考图时仍导出文本与 Prompt，并在结果里说明该角色需自行生成图
- [x] 5.5 导出结果报告写入的节点清单，并明示未创建任何连线、未触发生成（spec 权限边界）
- [x] 5.6 测试：一集导出的节点种类与数量；重复导出 id 一致；无参考图角色的 skipped notes；结果报告含「未连线未生成」声明

## 6. 导回归集（spec: infinite-canvas-bridge 导回推送与归集）

- [x] 6.1 从旧桥照搬配对策略：按分镜顺序填入还没有 `clipPath` 的片段/分镜，`targetIsSegment` 决定落 `segments/`（写 `StudioSegment.clipPath`）还是 `clips/`（写 `StudioShot.clipPath`）
- [x] 6.2 配对依据改为节点 `metadata.v8`（design D4），不再依赖 mtime 扫描或标题文本；选中的节点无该元数据时报告「无法配对」并列出节点，不猜
- [x] 6.3 写回 `clipPath` 时同步把状态推到 `SegmentStatus.done`（照搬旧桥：clipPath 有了而状态仍 pending 会让看板显示「待生成」却带着成片）
- [x] 6.4 复制而非移动：无限画布侧原始产物不动
- [x] 6.5 未选中集时报需要先选目标集，不自行猜测；视频多于片段时把未配对的明确报告出来，不静默丢弃
- [x] 6.6 测试：片段级与分镜级两条落盘路径；按分镜顺序填充；已 `done` 的片段不被覆盖；多余视频进 unassigned；无 `metadata.v8` 的节点不猜

## 7. 画布节点插件（spec: infinite-canvas-bridge 插件安装与持久化 / 生成用用户自己的渠道 / 权限边界）

- [x] 7.1 `services/infinite_canvas_canvas_plugin_source.dart`：内嵌自包含插件 JS 源码，V8 在 `/v8-plugin.js` 签发。用 `runtime.React`（不打包自己的 React），走 `evaluatePluginSource` 的 default/plugin 双出口约定
- [x] 7.2 插件实现 `CanvasPlugin`：id、name、version、`minAppVersion`；nodes 含文本与图片两类；`setup` 里做握手
- [x] 7.3 插件面板的「导入」动作（design D11）：`GET /api/episodes` 拉剧集 + 集列表 → 面板内下拉选集 → `GET /api/export` → 图片 URL 经 `uploadImage` 入库拿 storageKey → `applyOps` upsert 节点，`metadata.v8` 写入 V8 标识（design D3/D4）
- [x] 7.4 插件面板的「归集」动作（design D11）：读**选中视频节点自身**的 `metadata.v8` 与 `storageKey` → 取 Blob → `POST /api/import`。目标集来自节点元数据，不额外要求用户选择
- [x] 7.5 插件的错误呈现：服务未运行、密钥不符、版本过低都在画布上给可读提示，不只 console.error
- [x] 7.6 插件不碰 connections、不写节点生成状态、不读渠道配置——只写内容节点与素材
- [x] 7.7 【待手工验证】本地起 compose：本地起 compose → 装插件 → 面板里选集导入 → 画布上节点与参考图可见 → 无限画布里配好渠道 → 生成 → 面板里选中视频节点归集 → V8 剧集数据里 `clipPath` 就位

## 8. UI（spec: infinite-canvas-studio 打开工作台 / infinite-canvas-bridge 传输通道）

- [x] 8.1 `ui/infinite_canvas_studio_page.dart`：从旧页面改造。保留状态卡、启动/停止、构建入口、失败卡、容器日志；删掉「数据位置」卡（没有数据目录了）、bun 镜像站输入框、自动启动开关
- [x] 8.2 配置卡字段：工程目录、工作台端口、资产桥端口、退出即停（4 项，不再有镜像站与自动启动）
- [x] 8.3 「打开工作台」仅在就绪时可点；未就绪时展示当前阻塞原因（照搬旧实现）
- [x] 8.4 新增「安装画布插件」卡：显示插件 URL、一键复制、安装状态与心跳结果（design Risks 第六条）
- [x] 8.5 `ui/infinite_canvas_asset_bridge_panel.dart`：**只做状态与报告**——资产桥服务状态、最近一次导入/归集的报告。剧集下拉与两个动作都在插件面板里（design D11），V8 侧不再放一份，避免两个真相来源
- [x] 8.6 `ui/infinite_canvas_log_viewer.dart`：从旧日志查看器改造，构建期与容器期两种标题
- [x] 8.7 UI 契约测试照搬旧 `toonflow_ui_contract_test.dart` 的结构，断言改为新文案；确认「未启动」初始态、就绪前打开按钮不可点、能力边界说明可见

## 9. 彻底移除 Toonflow

- [x] 9.1 删 `lib/tools/toonflow_studio/`（11 文件）与 `test/tools/toonflow_studio/`（7 文件）
- [x] 9.2 `lib/services/app_paths.dart` 删 `toonflowDir` / `toonflowDataDir` 与 `allDirs` 登记；`test/app_paths_test.dart` 同步删断言（含「toonflowDataDir 必须挂在 root 下」那条与 settings.json 存在性检查）
- [x] 9.3 `lib/main.dart` 退出处置改调 `InfiniteCanvasComposeService.instance.disposeOnExit()`
- [x] 9.4 `lib/tools/registry.dart` 换 import 与 `ToonflowStudioToolDefinition` → `InfiniteCanvasStudioToolDefinition`；`lib/tools/tool_definition.dart` 的 `kToolIdToonflowStudio` → `kToolIdInfiniteCanvas`，标题「无限画布」，副标题去掉「与短视频工坊互传资产」里指向 Toonflow 的措辞
- [x] 9.5 `test/frequently_used_tools_test.dart` 的 AI 分类断言改为 `{'ai-assistant','ai-video-studio','agnes-playground','infinite-canvas','novel-manager'}`（该文件注释记录过两次漏改，这次一并改）
- [x] 9.6 删 `docs/toonflow_studio.md`，写 `docs/infinite_canvas.md`：架构图、端口表、插件安装步骤、与 Toonflow 版的差异说明（为什么没有数据目录）
- [x] 9.7 归档本 change 时删 `openspec/specs/toonflow-studio/` 与 `openspec/specs/toonflow-asset-bridge/`，把两个新 spec 目录落成正式 spec

## 10. 验证

- [x] 10.1 `dart analyze lib/ test/` 无新增 error / warning
- [x] 10.2 `flutter test test/tools/infinite_canvas/ test/app_paths_test.dart test/frequently_used_tools_test.dart` 全绿
- [x] 10.3 全量 `flutter test`：确认没有因删工具而红的残留断言（grep `toonflow` 应只剩 archive 目录里的历史 change）
- [x] 10.4 `grep -ri toonflow lib/ test/ docs/ openspec/specs/` 结果为空（archive 与 `openspec/changes/` 下的历史记录除外）
