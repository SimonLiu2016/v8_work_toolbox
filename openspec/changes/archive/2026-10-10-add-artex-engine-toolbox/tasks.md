## 1. Spike 结论固化（先确认环境基线）

- [x] 1.1 确认 `artex-ymh:local` 镜像存在于本机 Docker（`docker images | grep artex`），不存在则按 design D4 的三个构建参数执行一次构建并记录实际耗时
- [x] 1.2 确认 artex 仓库 `docker-compose.yml` 的 `artex` service 有 `image: artex-ymh:local` 与 `build` 双写（缺失则 `up` 会尝试现场构建）
- [x] 1.3 撤销 spike 期间对 `docker-compose.yml` 的直接修改（`ARTEX_GATE` 那段），确认改由 override 承担；`git diff docker-compose.yml` 应只剩 override 机制不涉及的内容
- [x] 1.4 手工验证一次「override + 关闭门控」的最小组合：生成 override、`docker compose up -d`、`curl /api/health` 返回引擎 JSON 而非 HTML

## 2. 模块骨架与注册

- [x] 2.1 创建 `lib/tools/artex_engine/` 目录结构（`models/`、`services/`、`ui/`）
- [x] 2.2 在 `lib/tools/registry.dart` 新增 `ArtexEngineDefinition extends ToolDefinition`：id `artex-engine`、title「ARTEX 渗透引擎」、category `ToolCategory.security`、`openInNewWindow` 保持默认 false（design D7），并追加到 `ToolRegistry.tools`
- [x] 2.3 在 `lib/services/app_paths.dart` 新增 `artexDir` getter（`<root>/artex`）并登记进 `allDirs`
- [x] 2.4 更新 `test/app_paths_test.dart` 的目录断言集纳入 `artexDir`
- [x] 2.5 创建占位 `ui/artex_engine_page.dart`，确认工具在活动栏 security 分类下可见、可点开、无异常

## 3. 配置模型与持久化

- [x] 3.1 实现 `models/artex_engine_state.dart`：容器状态机（idle / starting / running / stopping / stopped / failed）+ 失败原因字段
- [x] 3.2 实现配置读写：工程目录（默认 `~/Workspace/github/artex-ymh`）、HTTP 端口（默认 8787）、代理端口（默认 8788）、退出即停开关（默认 true）、门控开关（默认 off）、三个构建参数（默认 npmmirror / goproxy.cn / aliyun），全部经 `SettingsStore.readToolConfig/writeToolConfig('artex-engine')`
- [x] 3.3 实现工程目录定位校验：目录存在且含 `docker-compose.yml` 才通过，否则返回可读的失败原因（spec「Compose 工程定位」）

## 4. Override 生成与管理

- [x] 4.1 实现 override 生成：`services` 段只含 `artex` 的 `environment.ARTEX_GATE` 与 `ports`（带 `!override` 标签，避免 compose 追加合并导致 8787 双绑）
- [x] 4.2 实现标记识别：生成文件头部写入固定标记注释；重写前读取现有内容，非本工具生成的文件先备份（`.bak-<timestamp>`）再替换，并在 UI 告知
- [x] 4.3 端口配置变化时更新 override 的端口段
- [x] 4.4 单测：override 内容含门控关闭与配置端口；`!override` 标签存在；端口变化后内容正确更新；非本工具生成的文件被备份而非静默覆盖

## 5. 容器生命周期服务

- [x] 5.1 实现 `services/artex_compose_service.dart`：`ChangeNotifier` 单例，`docker compose -f docker-compose.yml -f docker-compose.override.yml` 统一入口
- [x] 5.2 实现 `docker info` 守护进程探活，失败给出「Docker 未运行」+ 跳转 `open -a Docker`；文案说明刚启动可能未就绪
- [x] 5.3 实现启动前端口预检：`ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false)` 试探后立即关；冲突则报具体端口号且不调 docker（design D3）
- [x] 5.4 实现 `up -d` + 健康探测循环：总预算 60s、每 1s 一次；判定要求 HTTP 200 且响应体为可解析 JSON 且含引擎服务标识字段（design D2 / spec「健康就绪判定必须校验响应体」）
- [x] 5.5 实现就绪超时处理：附容器 `logs --tail` 末若干行；额外检测响应体是否为已知欢迎页特征，是则定向提示「门控已开启」而非泛泛超时
- [x] 5.6 实现 `stop`；停止失败报告失败原因而非假装已停止
- [x] 5.7 实现 `disposeOnExit()`：按开关决定是否 `stop`；清理异常不阻止退出（与 mihomo 同一守卫语义）
- [x] 5.8 在 `lib/main.dart` 的 `runShutdownCleanup()` 挂载 `ArtexComposeService.instance.disposeOnExit()`
- [x] 5.9 单测（用可注入的进程执行器）：状态机转换正确；端口冲突时未调用 docker；HTML 响应判定未就绪；健康 JSON 判定就绪；stop 失败上报

## 6. 镜像构建服务

- [x] 6.1 实现 `services/artex_image_build_service.dart`：`docker compose build` 流式输出，构建期间禁止重复触发
- [x] 6.2 实现三个构建参数注入（`NPM_REGISTRY` / `GOPROXY` / `APT_MIRROR`），值来自配置
- [x] 6.3 实现失败模式匹配表（design D4 四类）：Docker 不可达 / 镜像源 403 / 网络超时 / 缺少环境变量
- [x] 6.4 增加 playwright 下载步骤失败的专项识别（输出含 `playwright install` 或 azureedge），提示检查 VPN 并说明已完成的层有缓存、重试不从零开始
- [x] 6.5 未命中任何模式时回退展示原始输出尾部（保留可诊断性）
- [x] 6.6 单测：四类模式各命中对应提示；playwright 专项命中；未知错误回退原始输出

## 7. 根 CA 引导

- [x] 7.1 实现 `services/artex_ca_service.dart`：检测 `<工程目录>/data/traffic/_ca/mitmproxy-ca-cert.pem` 是否存在（引擎未运行则不存在）
- [x] 7.2 实现系统信任库检测：通过 `security find-certificate` 判断是否已安装，避免重复引导
- [x] 7.3 生成安装命令（`sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <pem>`）并提供一键复制；UI 明示系统级影响与需自行卸载
- [x] 7.4 单测：三种状态（未生成 / 已生成未装 / 已装）各自给出正确呈现；命令字符串包含正确的证书路径

## 8. 主页面 UI

- [x] 8.1 实现 `ui/artex_engine_page.dart` 布局：标题 + 启停开关、状态行、地址行、工程目录行（可改）、端口配置（可改）、退出即停开关、构建镜像按钮、打开工作台按钮、查看日志按钮
- [x] 8.2 状态呈现与按钮可用性联动：未就绪时「打开工作台」不可点；构建中禁用重复触发；启动中超时前展示等待态
- [x] 8.3 端口冲突时在界面上明确指出是哪个端口被占用，并允许就地修改后重试（spec「端口分配与冲突预检」）
- [x] 8.4 实现 `ui/artex_log_viewer.dart`：容器日志 `logs --tail` 展示；构建时复用为构建日志视图
- [x] 8.5 「数据位置」说明区：写明 PG 命名卷与 `<工程目录>/data` 的实际路径，说明删除本软件不删除引擎数据（design D6 / Risks）
- [x] 8.6 能力边界说明区：明示 chisel / suo5 未预置，开箱范围为外网自动化探索（spec「能力边界明示」），首次进入可见
- [x] 8.7 CA 引导区按 7.1~7.3 的三态呈现

## 9. 回归与文档

- [x] 9.1 跑 `flutter test`，确认 `test/frequently_used_tools_test.dart`（分类非空 / 成员精确匹配）、`test/app_paths_test.dart`、`test/window_service_initialization_test.dart` 全绿
- [x] 9.2 端到端手工验证：首次启动（无镜像）→ 构建 → 启动 → 就绪 → 打开工作台；停止；改端口重试；退出即停开关两态
- [x] 9.3 编写 `docs/artex_engine.md`：运行前提（Docker Desktop、默认工程路径、compose 最低版本）、数据位置表、CA 安装与卸载说明、能力边界、AGPL 边界说明（design Risks 最后一条）
- [x] 9.4 按 `GEMINI.md` 要求执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，确认新工具在安装后的应用中可见可用
