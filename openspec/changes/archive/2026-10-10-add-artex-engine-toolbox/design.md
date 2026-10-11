## Context

动机见 proposal.md 的 Why。这里只记录塑造实现的既有状态与约束。

**引擎侧已确认的事实**（来自 2026-10-10 spike，全部实测）：

| 事实 | 来源 |
|---|---|
| 镜像 `artex-ymh:local` 1.67GB，三阶段构建耗时约 9 分钟 | `docker compose build` 实测 |
| 编排组两个 service：`postgres`（5432，不映射宿主机）+ `artex`（8787 全接口、8788 仅回环） | `docker-compose.yml` |
| `/api/health` 在认证中间件中显式豁免，无 token 可探测 | `server/auth.go:147` |
| 引擎的 `-addr` / `-proxy` 支持端口覆盖，但 compose 写死了映射 | `cmd/artex/main.go:61-63` |
| 门控按「进程内监听地址」判定：容器内绑 `:8787` 即被判定为非 loopback 而自动开启 | `server/gate.go:113` |
| 门控开启时所有请求（含 `/api/health`）返回逐字节固定的假 nginx 欢迎页（HTTP 200） | spike 实测 |
| 根 CA 落地在 `<data>/traffic/_ca/mitmproxy-ca-cert.pem`，目录权限 700/600 | `traffic/traffic.go:552` + spike 实测 |
| 流量代理有口令，存 `<data>/traffic/_auth`（0600，宿主机读不了，需 `docker exec`） | spike 实测 |
| 引擎数据：命名卷 `artex-ymh_pgdata` + 绑定挂载 `./data`，都在 artex 仓库目录 | `docker-compose.yml` |
| 17 工具层中 chisel / suo5 未预置二进制，启动日志明确报 `no such file or directory` | spike 实测 |

**本项目的既有可复用件**：

- `AppPaths` 是本地路径唯一源（`lib/services/app_paths.dart`），新增数据路径必须在那里登记并进 `allDirs`/`allFiles`，由 `test/app_paths_test.dart` 回归。
- `SettingsStore.readToolConfig/writeToolConfig` 是工具级小配置的标准存放处（`<root>/config/<toolId>.json`，原子写）。
- `SecurityProcessRunner` 已有 PATH 加固与子进程超时模式可参考（`lib/tools/security_toolbox/services/security_process_runner.dart`）。
- `MihomoProcessManager` 提供了本项目的「内嵌二进制进程生命周期」范式：启动后轮询 HTTP 就绪、启动超时即回滚、崩溃回调（`lib/tools/network_proxy/services/mihomo_process_manager.dart:96-125`）。
- `NetworkProxyService` 是「应用级服务单例 + 启停 + 持久化配置」的参照（`lib/tools/network_proxy/services/network_proxy_service.dart:44-266`）。
- `main.dart:366` 已有 SIGTERM → `runShutdownCleanup()` 的退出清理收敛点，mihomo 与本地词典桥都挂在那里。
- 工具注册契约是纯抽象类 `ToolDefinition`（`lib/tools/tool_definition.dart:38`），registry 一处注册即可（`lib/tools/registry.dart:474`）。
- 应用未启用 App Sandbox（`macos/Runner/Release.entitlements` 无 `com.apple.security.app-sandbox`），`Process.start` 绑定回环端口、读写任意路径均可用。

**关键约束**：本工具不引入任何新 pubspec 依赖。所有 Docker 交互走 `Process.start('docker', [...])`，HTTP 探测走已有的 `http` 包，浏览器打开沿用项目既有的 `Process.run('open', [url])` 先例（`lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart:18`，该处注释明确说明为何不引 `url_launcher`）。

## Goals / Non-Goals

**Goals:**
- 把「启停引擎 + 打开工作台」压缩到一次点击，且失败时可诊断、可重试。
- 让所有运行时配置（门控、端口）经由 override 注入，上游工程文件零修改。
- 让健康就绪判定无法被门控的假 200 页欺骗。
- 让「构建镜像」这个按钮能处理真实的高频失败模式，而非裸抛构建输出。
- 退出时容器处置确定，且永不触碰引擎数据。

**Non-Goals:**
- 不复刻引擎的任何 UI，不做 Flutter 侧 API 客户端（spec：`artex-engine` 的「打开引擎工作台」明确排除）。
- 不内嵌 Go 二进制，不用 FFI。
- 不改造现有安全工具箱；两者并存，退役决策留给用户。
- 不做引擎的多实例管理、远程 Docker 主机支持。
- 不自动安装根 CA、不自动修改系统信任库。

## Decisions

### D1: 用 `docker-compose.override.yml` 承载全部运行时配置

**选择**：本工具在工程目录生成并维护 `docker-compose.override.yml`，所有运行时差异（`ARTEX_GATE=off`、端口映射）都写在这里，通过 `docker compose -f docker-compose.yml -f docker-compose.override.yml` 使用。

**为什么不改 `docker-compose.yml`**：spike 里我确实直接改了原文件加 `ARTEX_GATE`，验证可行。但那不可持续——用户 `git pull` 一次就丢了，且会让 artex 仓库出现本地未提交改动，干扰后续升级。override 是 compose 原生机制，语义上正是「本地部署差异」，且对上游零侵入。

**备选**：
- 改 `docker-compose.yml` — 被上游更新覆盖，已否（上面）。
- 用 `docker compose run -e` 传环境变量 — 只能传 env，改不了端口映射（端口是 compose 文件的 `ports` 段，不是 env），否。
- 完全用自己的 compose 文件替换上游 — 要复制上游全部内容，上游改结构就烂，否。

**实现要点**：override 只写 `artex` 服务的差异段。compose 的 override 语义是「同名键合并、`ports` 整体替换」，所以端口那段写全量即可。

```yaml
# docker-compose.override.yml（本工具生成）
services:
  artex:
    environment:
      ARTEX_GATE: "off"
    ports: !override
      - "127.0.0.1:${ARTEX_HTTP_PORT}:8787"
      - "127.0.0.1:${ARTEX_PROXY_PORT}:8788"
```

`!override` 标签必须带：compose 对 `ports` 的默认合并行为是追加，不带标签会导致 8787 同时绑两个端口（原文件的 `"8787:8787"` 还在）。

**风险**：若用户手工改过 override，工具重写会冲掉。缓解：生成前读取现有内容，仅在识别出是本工具生成（带标记注释）时才重写；不是则备份后替换并告知。

### D2: 健康探测校验响应体，不只看状态码

**选择**：探测 `/api/health`，要求 HTTP 200 且响应体是可解析 JSON 且含 `service` 字段值为引擎标识。HTML 响应直接判为未就绪。

**为什么**：这是 spike 最关键的发现。门控开启时返回的是逐字节固定的假 nginx 页，状态码 200、内容 14KB 左右。任何只看状态码的实现在这个场景下会误判就绪，然后把用户送到一个假页面前。spec 的「健康就绪判定必须校验响应体」即由此而来。

**备选**：探测其他端点 — `/api/auth/status` 同样受门控与认证影响，且语义上不如 `/api/health` 干净（后者在 `requireAuth` 中显式豁免）。否。

**实现要点**：解析用 `jsonDecode` + try/catch。超时预算要宽松——spike 实测容器起来后 2 秒内就绪，但首次运行要做 schema 初始化，给 60 秒总预算、每 1 秒一次轮询更稳。

### D3: 端口预检用 `ServerSocket.bind` 在启动前拦

**选择**：启动前对两个端口做 `ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false)` 试探，绑得上立刻关掉放行，绑不上报冲突。冲突时根本不调 docker。

**为什么**：若让 compose 先失败再解析输出，错误信息形如 `Bind for 0.0.0.0:8787 failed: port is already allocated`，且容器可能进入半启动状态（postgres 已起、artex 失败），需要额外清理。预检把失败前移到用户可理解的点上。

**备选**：解析 compose 输出 — 如上，状态残留且文案难读，否。

**注意**：预检只覆盖宿主机侧。容器内 8787 不变（override 只改宿主机映射），所以引擎内部看到的端口始终是 8787，不需要给引擎传 `-addr`。这让 D1 的 override 只需改 `ports` 一段。

**项目先例**：`mihomo_process_manager.dart:300` 已有用 `ServerSocket.bind` 探端口冲突的做法，沿用同一模式。

### D4: 构建失败诊断做成模式匹配表

**选择**：`ArtexImageBuildService` 捕获构建输出，按一组正则匹配已知失败模式，命中则给出对应指引；未命中才回退为展示原始输出尾部。

至少四类（spec「镜像构建入口与失败诊断」要求的下限）：

| 模式特征 | 提示 | 出处 |
|---|---|---|
| `Cannot connect to the Docker daemon` / `docker.sock` | Docker 未运行，给跳转按钮 | spike 前实测 |
| `403 Forbidden` 且含 `mirror` / `registry` | 镜像加速器失效，引导检查 Docker Engine 镜像源 | spike 实测（第一次构建就是死在这） |
| `Client.Timeout` / `request canceled` / `context deadline` | 网络不通，检查代理/VPN | spike 实测（Docker Hub 直连超时） |
| `POSTGRES_PASSWORD` / `未提供 database` / `.env` | 缺少环境变量，给生成默认值入口 | spike 前预检发现 compose 强校验 |

**为什么值得单做一层**：spike 证明这是最高频的失败——第一次构建 100% 死在镜像源 403 上，而它的输出对用户毫无指引意义。

**三个上游构建参数可配**：`NPM_REGISTRY` / `GOPROXY` / `APT_MIRROR`，默认 `registry.npmmirror.com` / `goproxy.cn,direct` / `mirrors.aliyun.com`（spike 用这三个值 9 分钟构建成功）。存 `SettingsStore.readToolConfig('artex-engine')`。

**已知无法覆盖的失败**：`playwright install --with-deps chromium` 走 `playwright.azureedge.net`、nodesource 走 `deb.nodesource.com`，都不受上述三个参数控制。这一步失败只能提示检查 VPN。这条要写进 Risks。

### D5: 容器生命周期服务单例 + ChangeNotifier

**选择**：`ArtexComposeService extends ChangeNotifier`，单例，持有状态机 `idle → starting → running → stopping → stopped` 加 `failed(reason)`。所有 docker 调用是 `Process.start('docker', ...)` 串行执行，UI 只读状态。

**为什么**：与 `NetworkProxyService` 同构，项目里已有成熟范式；`ChangeNotifier` 足够（不需要 stream，状态转换少且都是用户触发）。

**为什么不复用 `SecurityProcessRunner`**：那个是给「一次性 CLI 命令」设计的（`Process.run` + 超时 SIGKILL）。容器编排需要长轮询、日志流、以及「启动失败要保留容器日志」——`docker compose up -d` 返回后还得等健康探测，这期间的容器日志要留着。所以独立实现，但 PATH 加固与环境变量注入的做法借过来。

**退出清理**：在 `runShutdownCleanup()`（`main.dart:475`）里挂一个 `ArtexComposeService.instance.disposeOnExit()`，仅在开关打开时执行 `docker compose stop`。清理失败不阻止退出——与 mihomo 那条守卫同一语义（注释已写明「清理失败 MUST NOT block exit」）。

### D6: 配置存 `SettingsStore`，数据不归 `AppPaths`

**选择**：本工具的配置（工程目录、两个端口、退出即停开关、三个构建参数、门控开关）存 `SettingsStore.readToolConfig('artex-engine')`。`AppPaths` 只新增一个 `artexDir` 用于存放工具自己生成的 override 备份与日志副本，并登记进 `allDirs`。

引擎的数据（PG 卷、`./data`）**不进 `AppPaths`**——它归 Docker 与 artex 仓库管，生命周期独立。这点必须在代码注释与文档里写明，否则以后做备份/导出会漏，或者误以为删 `AppPaths.root` 就能清干净。

**为什么**：`AppPaths` 的语义是「本软件生成的本地数据」。引擎数据不是本软件生成的，把它纳入会破坏这个语义，也会让 `app_paths_test.dart` 的单一性断言失去意义。

### D7: 主窗口内嵌，不独立窗口

**选择**：工具以 `openInNewWindow: false`（默认）内嵌主窗口。

**为什么**：参照对象选错了会很难用。安全工具箱用独立窗口，因为它的扫描是长进程、主窗口被挤占时不该中断。但本工具自己不跑任何长进程——它只发号施令，真正干活的是容器。容器不随窗口生死。所以独立窗口没有收益，反而多一层 `WindowKind` + `WindowServices.required` + `main.dart` 分支的接线成本（`main.dart:51-160, 278`）。

## Risks / Trade-offs

**[Docker Desktop 未运行或正在启动] → 预检并给跳转。** spike 中遇到过 `Cannot connect to the Docker daemon`。启动/构建前先 `docker info` 探活，失败则提示并提供 `Process.run('open', ['-a', 'Docker'])`。注意 Docker Desktop 刚启动时 daemon 可能还没就绪，提示文案要说明这一点而不是让用户以为没装。

**[chromium 下载步骤无国内源，构建可能在这一步失败] → 提示检查 VPN，并允许重试。** `Dockerfile.source` 的三个构建参数管不到 `playwright.azureedge.net` 与 `deb.nodesource.com`。spike 这次靠 VPN 过了，但换网络环境仍是最高风险的一步。缓解：把该步骤的失败单独识别为一个模式（输出含 `playwright install` 或 azureedge），提示「此步骤需访问 playwright 下载源，请检查 VPN 后重试；已完成的层有缓存，重试不会从零开始」。

**[门控开启导致健康探测拿到假 200] → D2 的响应体校验 + D1 的 override 注入双保险。** 但若用户手工关掉了 override 或自己改了 compose 让门控开启，仍会进入「60 秒超时」路径。缓解：超时后除容器日志外，额外检测一次「响应体是否为已知的欢迎页特征」，若是则直接给出「门控已开启」的定向提示而不是泛泛的超时。

**[端口预检通过但 compose 仍绑定失败] → 保留失败后的容器日志。** 竞态窗口存在（预检后到 compose 绑定前端口被抢）。概率低，但发生后必须有日志可查，否则用户无从下手。

**[用户手工编辑 override 被冲掉] → 生成前识别标记，非本工具生成的文件先备份。** 见 D1。

**[`docker compose` 版本差异] → 只用稳定子集。** 本机是 compose v5.5.1。为避免版本间行为差，只用 `up -d` / `stop` / `down` / `ps` / `logs --tail` / `build` 这几个稳定命令，不用 `--profile`、`watch` 等较新特性。`!override` YAML 标签在 compose v2.20+ 支持，需在文档注明最低版本要求。

**[引擎数据不在 `AppPaths` 管辖内，备份方案可能漏] → 文档 + 工具界面明示。** 在工具界面放一节「数据位置」，写明 PG 卷与 `./data` 的实际路径，并说明删除本软件不会删除引擎数据。

**[AGPL 边界的意外突破] → 严格保持进程边界。** 当前设计是纯子进程 + HTTP 打开，无代码链接、无源码复制，风险很低。但若未来有人想「优化体验」而在 Dart 侧实现引擎 API 客户端，那仍然是进程间通信，不构成衍生；真正会突破边界的是把 artex 的 Go 源码复制进本仓库编译。这一点写进文档，防止后续演进时踩线。

## Migration Plan

纯增量，无数据迁移、无破坏性变更：

1. 新增 `lib/tools/artex_engine/` 模块，registry 注册一个条目。
2. `AppPaths` 新增 `artexDir` 并进 `allDirs`（同步更新 `test/app_paths_test.dart` 的断言集）。
3. `main.dart` 的 `runShutdownCleanup()` 挂容器处置。
4. 用户侧动作：确保 Docker Desktop 运行、确保 artex 仓库在默认路径（或在工具里改路径）、点一次「构建镜像」（若镜像未建）、启动。

**回滚**：删除工具注册条目与模块目录即可，不影响任何既有功能。引擎侧若停用本工具，手工 `docker compose up -d` 照常可用。override 文件可留可删（删了就是上游默认行为）。

## Open Questions

- **是否需要支持引擎的多工程（多个 artex 副本）**：当前设计单工程。多工程意味着每个工程一份 override 与一组端口，复杂度上升但模式相同。可在首次使用后根据实际需要再决定，不影响现有 spec 与任务拆分。
- **根 CA 的卸载引导是否要做**：spec 只要求安装引导（D6 non-goal 明确不自动装）。卸载是系统级操作且低频，当前不做；若后续发现需要，作为独立小需求追加，不改变现有架构。
