## Context

现状与约束（实现细节见 proposal.md 的 Impact 与各 delta spec）：

- 本仓库已有 `artex-engine` 这一「容器化外部引擎托管」的完整先例：`ProcessRunner` 注入抽象、`ArtexComposeService` 的六步启动序列、`ArtexOverrideStore` 的 override 机制、`ArtexBuildFailureKind` 的失败模式分类、`ArtexConfigStore` 的 `SettingsStore` 薄封装。本设计的目标是让 Toonflow 工具与它**结构同构**，使后续维护者能直接迁移经验。
- Toonflow 上游 `compose.yaml` 用命名卷 `toonflowData:/app/data`，`Dockerfile` 以非 root 用户 `bun` 运行，镜像内已 `mkdir -p data/workspaces/myProject`。
- Toonflow 服务端（Express 5 on Bun）**没有任何健康端点**；`app.listen(3000)` 后直接挂路由。业务 API 绝大多数不带鉴权，少数控制类端点要求 `x-toonflow-workspace: 1` 头 + 同源 Origin。
- 静态资源由同一进程服务，因此任意路径在 API 未就绪时也可能返回 200 的 HTML。
- 本机当前 Docker 守护进程未运行（socket 不存在），`Docker.app` 已安装于 `/Applications`。磁盘可用约 25GB。

## Goals / Non-Goals

**Goals:**

- 与 `artex-engine` 结构同构的容器生命周期托管，可测试性来自 `ProcessRunner` 注入而非真实 docker。
- 用 **bind mount 替代命名卷**，使资产桥能直接文件系统读写媒体（避免 HTTP 传输大文件）。
- 健康探测用一个便宜且无鉴权的端点，并以「响应体是 JSON」作为就绪判据。
- 密钥边界成为可执行约束：`settings.json` 的访问次数为零，且可被测试断言。

**Non-Goals:**

- 不内嵌 WebView 或复刻 Toonflow UI（沿用 `artex-engine` 的 spec 先例）。
- 不引入 `webview_flutter` / `url_launcher` / `dio` 等新依赖。
- 不接入 Toonflow 的 MCP（`/mcp`，默认 10588）或 A2A（`/a2a`）——两者都需要额外的令牌管理与授权模型，超出本变更范围。
- 不解决「Toonflow 的密钥明文存储」这一上游问题；本设计只保证本软件不碰它。

## Decisions

### 决策 1：健康探测用 `GET /api/workspaces/list`，判据是 JSON 响应体

探测端点选择：该路由无 `assertAppRequest`、无参数、返回 `{ code, data, message }` 信封，是最便宜的可用探针。

就绪判据：`status == 200` **且**响应体可解析为 JSON 对象 **且** 含 `code` 字段。

- **备选 A：`GET /api/ai/models`**。否决：它会在没有配置供应商时也可能正常返回空数组，无法区分「进程起来了」与「进程没起来」——虽然 `workspaces/list` 也返回 JSON，但它会真实触达 `conf` 与文件系统初始化路径，覆盖面更接近「服务可用」。
- **备选 B：探测 `/` 并接受 HTML**。否决：正是 spec 要防的误判。
- **备选 C：`docker compose ps` 判断容器 running 即就绪**。否决：容器 running 不等于服务可用（Toonflow 首次启动要初始化插件），ARTEX 的 spike 已经踩过这个坑。

### 决策 2：bind mount 注入 `user: "<uid>:<gid>"`

上游容器以 `bun` 用户（uid 1000）运行，其对 `/app/data` 的写入权限来自 Dockerfile 的 `chown -R bun:bun data`——但那只作用于镜像层内的目录。bind mount 宿主机目录后，容器内进程看到的是宿主机文件的属主。

override 注入 `user: "<uid>:<gid>"`，uid/gid 由 `id -u` / `id -g` 在启动时取得。

**spike 实测（2026-10-11，Docker Desktop 29.8.2）**：

| 方案 | 容器内身份 | 写 `/app/data` | 宿主机可见 |
|---|---|---|---|
| 不加 `user:` | `uid=1000(bun)` | ✅ | ✅ |
| `user: "501:20"` | `uid=501 gid=20` | ✅ | ✅ |

Docker Desktop 的文件共享层（VirtioFS / gRPC-FUSE）实际上绕过了 POSIX 权限，所以两种方案都能写。仍选 `user:` 的理由：让容器内进程以**宿主机当前用户**身份运行，这样即使 FUSE 行为变化、或将来换到 Linux 原生 Docker（权限不被绕过），写入依然成立。

- **备选 A：只 `chmod -R 777` 宿主机目录**。否决：全局可写会让 `settings.json`（含明文 Key）对其他本机用户可读，与密钥边界冲突。
- **备选 B：沿用命名卷，资产桥走 HTTP**。否决：HTTP 传输媒体会让「导回」变成几十兆的上传，体验不可接受。
- **备选 C：`user: "0:0"`（root）**。否决：容器内 root 写出的文件属主是 root，宿主机用户改不动，备份与清理都变麻烦。

### 决策 3：数据目录 `AppPaths.toonflowDataDir`，且只登记「本软件生成的产物」

```
~/Library/Application Support/V8WorkToolbox/
  toonflow/                 # 本工具自己的产物：override 备份、构建日志副本
  toonflow_data/            # 挂载到容器 /app/data
    workspaces/<series-id>/ # 资产桥读写的唯一范围
    assets/                 # Toonflow 全局素材库（用户可能在网页里手工放文件）
    settings.json           # ⚠ 本软件绝不读写
```

`toonflow_data/` 整体登记进 `AppPaths.allDirs`（备份范围），但 `settings.json` **不**登记进 `allFiles`——`allFiles` 的语义是「本软件生成并管理的文件」，把它放进去会诱导后续代码去碰它。

- **理由**：这是把「密钥边界」从注释升级为结构性约束的唯一办法。`test/app_paths_test.dart` 断言 `allFiles` 单一来源，`settings.json` 不在其中本身就是一条可执行的声明。

### 决策 4：资产桥只写「内容节点 + 素材」，不写 edges

画布 JSON 的最小可识别形状是 `{ toonflowCanvas: true, nodes: [...], edges: [], viewport: {...} }`。桥写出：

- 文本节点：`data.textPath = assets/<nodeId>/content.md`，对应文件写 Markdown
- 图片节点：`outputs.image = { dataType: "IMAGE", value: { url, mimeType } }`，`url` 为工作区相对路径，素材文件拷到 `assets/<nodeId>/`

`edges` 恒为空数组。连线与生成由用户在 Toonflow 内通过其 canvas Skill / Agent 完成。

- **备选 A：也生成 edges**。否决：Toonflow 的 canvas Skill 明确「不通过编辑画布 JSON 绕过工具」，且节点端口 ID 与引用顺序（`referenceOrder`）需要运行时协商，静态写出的边很可能与用户实际选择的模型能力不匹配，反而造成难以排查的半成品。
- **备选 B：直接写 Toonflow 的 `/api/assets/save`**。否决：那是 HTTP 二进制上传，与 bind mount 二选一；bind mount 已定，走文件系统更简单也更可控。

### 决策 5：节点 id 确定性派生，保证幂等

`nodeId = 'v8-' + sha1(seriesId + ':' + episodeId + ':' + kind + ':' + localId).slice(0,12)`，`kind ∈ {outline, worldview, character, scene, storyboard}`。

- **理由**：Toonflow 的节点 id 同时是 `assets/<nodeId>/` 的目录名。随机 id 会让重复导出产生孤儿素材目录；确定性 id 让「再次导出覆盖同名内容」自然成立，且用户重启后看到的是同一个画布。
- **校验**：id 必须匹配 Toonflow 的节点 id 约束（`/[\\/]/.test(nodeId)` 会抛错），sha1 hex 天然满足。

### 决策 6：构建参数只暴露一个（包管理器镜像站）

Toonflow 的构建是 `bun install --frozen-lockfile` + 构建节点/工具/web/server，不涉及 apt 或 go。因此只需一个可配置项：`BUN_CONFIG_REGISTRY`（默认 `https://registry.npmmirror.com`）。

- **理由**：ARTEX 的三个构建参数（npm registry / go proxy / apt mirror）是因为它要编译 Go 二进制；这里没有同类需求，多留配置项只会让用户面对无意义的选择。
- **失败模式**：保留 ARTEX 的四类（守护进程不可达 / 镜像源 403 / 网络超时 / 缺环境变量），另加「bun 锁文件与 package.json 不匹配」一类（`--frozen-lockfile` 的典型失败）。

### 决策 7：嵌入式页面，不建独立窗口

Toonflow 的所有长任务都在容器内执行，工具页面本身没有分钟级的进程内计算（构建是流式子进程，启动是 docker 命令 + 轮询）。这与 ARTEX 选择嵌入同理，避免 `WindowKind` + `WindowServices` + `main.dart` 三处接线。

## Risks / Trade-offs

- **[Risk 已消除] bind mount 不可写** → spike 实测 `user:` 生效（见决策 2），无需退路。
- **[Risk] 磁盘不足**（本机可用 25GB；实测镜像 1.84GB + 构建缓存峰值 10.32GB）→ Mitigation：构建前在 UI 显示「建议预留 15GB」的提示；`toonflow_data/` 的媒体由用户自行管理，不在本工具内做清理。
- **[Risk] 首次构建耗时很长且可能中途失败**（实测 13 分 32 秒，且首次真的失败了）→ Mitigation：流式日志 + 失败模式分类；构建超时定为 30 分钟；UI 在开始前明示「首次构建可能需要 10–20 分钟」；日志明确说明「已完成的层有缓存，重试不会从零开始」；构建期间禁止重复触发（单飞）。
- **[Risk] 上游仓库升级导致 `compose.yaml` 结构变化（如服务名从 `toonflow` 改名）→ override 失效** → Mitigation：override 用服务名 `toonflow` 定位；`up -d` 失败时解析输出，若出现「service toonflow not found」一类特征，给出「上游 compose 结构可能已变化，请检查服务名」的定向提示。
- **[Risk] 端口 3000 被用户本机其他服务占用** → Mitigation：默认端口不用 3000（上游文档与习惯都指向 3000，撞车概率最高），改用一个不常见值；同时保留端口预检与可配置。
- **[Risk] `settings.json` 被误读** → Mitigation：结构上不登记进 `allFiles`；单测断言一次导出/归集后该文件 mtime 不变；诊断日志经 `AiLogger` 之外的独立通道，不包含工作区外路径。
- **[Trade-off] 不接 MCP 意味着无法从本软件驱动 Toonflow 的画布** → 这是有意的：Toonflow 的画布操作语义（分页、截断、引用编号核对）极其复杂，从外部复刻一层只会得到不可靠的半成品。资产桥只负责「把内容送进去、把成品取回来」，中间的专业制作留给 Toonflow 自己的 Agent。

## Migration Plan

1. 数据层与配置：`AppPaths` 登记 + `ToonflowConfigStore` + `SettingsStore` 工具配置键。
2. `ProcessRunner` + `ToonflowComposeService`（含健康探测与 override）+ 单元测试（`FakeProcessRunner` 驱动全部失败分支）。
3. `ToonflowImageBuildService` + 失败模式测试。
4. UI 页面（状态卡、配置卡、日志查看器、数据位置卡、能力边界说明）。
5. 资产桥（导出 + 导回）+ 测试（含 `settings.json` mtime 断言）。
6. 工具注册 + `app_paths_test.dart` / `frequently_used_tools_test.dart` 同步。
7. 文档 `docs/toonflow_studio.md` + 手工 spike 验证（真实 docker 启动一次，确认 bind mount 可写、探测就绪、导出的画布能被 Toonflow 打开）。

回滚策略：全部为新增代码与新增配置键，无数据迁移；`toonflow_data/` 下的用户数据在卸载本软件后仍可由上游 compose 直接使用（把 bind mount 路径改回命名卷或指向同一目录即可）。

## Open Questions（2026-10-11 spike 已全部解决）

### 1. bind mount 的用户对齐 — 结论：`user:` 生效，且比"不加"更安全

spike 实测（Docker Desktop 29.8.2，macOS 26，oven/bun:1.3.14 复刻上游形态）：

| 方案 | 容器内身份 | 写 `/app/data` | 宿主机可见 | 结论 |
|---|---|---|---|---|
| 不加 `user:` | `uid=1000(bun)` | ✅ | ✅ | 可用，但目录属主是容器内 uid 1000 |
| `user: "501:20"` | `uid=501 gid=20` | ✅ | ✅ | **采用** |
| 目录属主非当前用户 | — | ✅ | ✅ | Docker Desktop 的 VirtioFS 实际绕过了 POSIX 权限 |

**关键发现**：Docker Desktop 的文件共享层（VirtioFS / gRPC-FUSE）把宿主机文件统一映射成容器内用户可读写，**POSIX 权限实际上被绕过**——所以"不加 `user:` 也能写"并不能说明它安全。选 `user: "501:20"` 的理由是让容器内进程以**宿主机当前用户**身份运行，这样万一 FUSE 行为变化、或将来换到 Linux 原生 Docker（权限不会被绕过），写入依然成立。

uid/gid 在启动时用 `id -u` / `id -g` 取得，写进 override。

### 2. 首次构建耗时 — 结论：约 13.5 分钟，镜像 1.84GB

首次 `docker compose build` 实测 **13 分 32 秒**，失败在 `bun install --frozen-lockfile`（TLS 握手超时，见下方"环境坑"），重跑后利用已缓存层完成。最终镜像 **1.84 GB**。

影响：
- 构建超时预算定为 **30 分钟**（首次含依赖下载，重跑有缓存会快得多）；
- UI 在构建开始前明示「首次构建可能需要 10–20 分钟」；
- 磁盘需求：镜像 1.84GB + 构建缓存（实测 10.32GB 峰值）+ 数据目录，建议预留 **15GB**。

### 3. 默认端口 — 结论：3177

实测本机占用：3000 空闲、8787 空闲、8797 被本应用占用（本地词典桥）、3177 空闲。取 **3177**——与 ARTEX（8787/8788）和词典桥（8797）都不相邻，误记率低。

### 附带发现：Docker Hub 在本机不可直连

`registry-1.docker.io` TLS 握手超时。已在 `~/.docker/daemon.json` 配置国内镜像源后解决。这不影响本工具的实现，但**首次构建失败的用户绝大多数会撞在这里**，所以失败诊断必须覆盖「镜像源/网络不通」这一类，且提示要指向 Docker Desktop 的镜像源配置。
