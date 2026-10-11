# Toonflow 漫剧工坊

通过 Docker 在本地跑 [Toonflow](https://github.com/Toonflow) 的官方工作台，并把它与「AI 短视频工坊」用一条资产桥连起来。本工具**不实现任何 Toonflow 能力**——它负责容器生命周期、数据落点与资产互传；创作在 Toonflow 自己的工作台里完成。

> 变更来源：`openspec/changes/add-toonflow-studio-toolbox/`（spike 2026-10-11，Docker Desktop 29.8.2 / macOS 26）。

---

## 1. 运行前提

| 依赖 | 说明 |
|---|---|
| Docker Desktop | 必须已安装**且正在运行**。页面上的「Docker Desktop」按钮可直接拉起 |
| Compose v2 | `docker compose`（子命令形式）。Docker Desktop 29.x 自带 |
| Toonflow 仓库 | 本地一份 checkout，需含 `Dockerfile` 与 `compose.yaml`。默认路径 `/Users/simon/Workspace/github/Toonflow-app`，可在配置卡里改 |
| 磁盘 | 镜像 1.84 GB + 构建缓存峰值 10.32 GB + 数据目录，**建议预留 15 GB** |
| 端口 | 默认 `3177`（只绑 `127.0.0.1`，不对局域网暴露） |

**首次构建约 13.5 分钟**（spike 实测 13 分 32 秒），UI 会在点下「构建镜像」前明示。重跑会复用缓存层。

### 环境坑：Docker Hub 可能不可直连

本机实测 `registry-1.docker.io` TLS 握手超时。若首次构建失败，先看失败卡给出的分类——「镜像源不可达」一类要去改 Docker Desktop 的镜像源配置（`~/.docker/daemon.json` 的 `registry-mirrors`），而不是开 VPN。构建期 bun 走 `bunRegistry`（默认 `https://registry.npmmirror.com`），同样可在配置卡修改。

---

## 2. 架构与职责切分

```
┌──────────────────────── V8WorkToolbox ────────────────────────┐
│  AI 短视频工坊（lib/tools/ai_video_studio/）                  │
│    剧集 / 分镜 / 角色卡 / 场景卡 / 片段                        │
│            │                                    ▲             │
│            ▼ 导出                                │ 复制回      │
│  ToonflowAssetBridge（lib/tools/toonflow_studio/services/）   │
│    只写「内容节点 + 素材」，不写 edges                         │
└────────────┼───────────────────────────────────────────────┘
             │ bind mount（文件系统直读直写）
             ▼
      ~/Library/Application Support/V8WorkToolbox/toonflow_data/
             │
             ▼  （挂到容器 /app/data）
┌──────────────────────── Toonflow 容器 ───────────────────────┐
│  官方 Express + Bun 服务 :3000 → 宿主机 127.0.0.1:3177        │
│  canvas Skill / Agent / 模型调用（密钥在它自己的 settings.json）│
└───────────────────────────────────────────────────────────────┘
```

| 组件 | 职责 | 明确**不做**的事 |
|---|---|---|
| `ToonflowComposeService` | 探活、端口预检、`up -d`、健康探测、`stop` | 不实现任何 Toonflow 业务能力 |
| `ToonflowImageBuildService` | `docker compose build` 单飞 + 流式日志 + 失败分类 | 不改上游 `Dockerfile` |
| `ToonflowOverrideStore` | 生成/重写 `docker-compose.override.yml` | 不改上游 `compose.yaml` |
| `ToonflowAssetBridge` | 导出内容节点与素材、导回视频 | 不写连线、不写生成状态、不碰模型配置 |
| `ToonflowConfigStore` | `config/toonflow-studio.json` 薄封装 | 不存任何密钥 |

---

## 3. 为什么用 override 而不是改上游 `compose.yaml`

spike 里直接改原文件验证过可行，但用户 `git pull` 一次就丢，且会让 Toonflow 仓库出现本地未提交改动、干扰后续升级。override 是 compose 原生的「本地部署差异」机制，对上游零侵入。

生成的三件事：

```yaml
services:
  toonflow:
    user: "501:20"
    ports: !override
      - "127.0.0.1:3177:3000"
    volumes: !override
      - "/Users/simon/Library/Application Support/V8WorkToolbox/toonflow_data:/app/data"
```

- **`ports: !override` / `volumes: !override` 是必须的**：compose 对这两个字段的默认合并行为是**追加**。不带标签会导致容器同时绑 3000 和 3177、`/app/data` 同时挂命名卷和 bind mount。
- **卷条目整条加引号**：只引宿主机路径段（`- "<host>":/app/data`）会被 compose v5 的 go-yaml 判成「块集合里少了 '-'」而拒绝加载整个文件。整条引起来两种需求都满足。
- **路径一定带引号**：macOS 的 `Application Support` 含空格，不加引号 YAML 会把它解析成两段。
- **非本工具生成的文件先备份**（`toonflow/docker-compose.override.yml.bak-<ts>`）再覆盖，且 `write()` 会返回是否发生了备份——用户文件被替换必须报告，不能静默。

### bind mount 与 uid/gid（spike 结论）

| 方案 | 容器内身份 | 写 `/app/data` | 宿主机可见 |
|---|---|---|---|
| 不加 `user:` | `uid=1000(bun)` | ✅ | ✅ |
| `user: "501:20"` | `uid=501 gid=20` | ✅ | ✅（**采用**） |

**关键发现**：Docker Desktop 的文件共享层（VirtioFS / gRPC-FUSE）把宿主机文件统一映射成容器内用户可读写，**POSIX 权限实际上被绕过**。所以「不加 `user:` 也能写」并不说明它安全。

选 `user:` 的理由是让容器内进程以**宿主机当前用户**身份运行：万一 FUSE 行为变化、或将来换到 Linux 原生 Docker（权限不会被绕过），写入依然成立。uid/gid 启动时用 `id -u` / `id -g` 取，取不到回退 `501:20`（macOS 首个真实用户的常见值）而不是让启动失败。

---

## 4. 健康就绪判定：必须校验响应体

Toonflow 的业务 API 与静态资源由**同一个进程**服务。API 没就绪时，任意路径也会返回 200 的 HTML（SPA 的 `index.html`）。只看状态码会把「服务未就绪」误判成「已就绪」，把用户送到一个打不开的工作台。

判据：`GET http://127.0.0.1:3177/api/workspaces/list` → 200 **且**响应体是可解析 JSON 对象、含 `code` 字段。HTML 一律判未就绪。

- 总预算 60 秒，轮询间隔 1 秒，单次探测超时 3 秒（spike 实测容器 4 秒内就绪；首次启动要做插件初始化，所以预算放宽）。
- 超时会在失败卡附上容器日志尾部 15 行。

---

## 5. 数据位置

| 路径 | 归谁管 | 内容 |
|---|---|---|
| `<root>/toonflow/` | **本软件** | override 备份、构建日志副本 |
| `<root>/toonflow_data/` | **容器** | 挂到 `/app/data`，工作区与素材都在这里 |
| `<root>/toonflow_data/workspaces/<series-id>/` | 容器 + 资产桥 | 画布 JSON 与 `assets/<nodeId>/` |
| `<root>/toonflow_data/settings.json` | **仅容器** | Toonflow 自己的供应商密钥，**明文** |
| `config/toonflow-studio.json` | 本软件 | 工具配置（工程目录/端口/开关/镜像站） |

`<root>` = `~/Library/Application Support/V8WorkToolbox`。

### 备份范围

备份 `toonflow_data/` 即可完整保留工作区、素材与 Toonflow 的配置。`toonflow/` 里的 override 备份可随时重新生成，不必备份。

---

## 6. 密钥边界（重要）

`toonflow_data/settings.json` 保存 Toonflow **自己**的供应商 API 密钥，**明文**（容器内 `chmod 600`）。用户已明确接受它落在 V8 数据目录内，约定的边界是：

> **V8 只读写 `workspaces/` 与 `assets/`，绝不碰 `settings.json`。**

这不是一句口头承诺，有三层机械约束：

1. **结构性**：`settings.json` **没有**登记进 `AppPaths.allFiles`。那个清单的语义是「本软件生成并管理的文件」——登记它等于邀请后续代码去碰它。
2. **测试**：`test/tools/toonflow_studio/toonflow_asset_bridge_test.dart` 在 `settings.json` 里写一个 canary 值，导出/导回后断言其 **mtime 与内容一个字节都不变**，并断言桥写过的所有文件里不含 canary。
3. **诊断**：资产桥与 compose 服务的错误文本只含路径与容器输出，不含任何配置文件内容。

---

## 7. 资产桥

### 导出（工坊 → Toonflow）

读剧集与目标集的 `worldview`、`styleTokens`、`synopsis`、分镜表、角色卡与场景卡（含参考图文件），在工作区里生成：

- `画布1.json` — `{"toonflowCanvas": true, "nodes": [...], "edges": [], "viewport": ...}`
- `assets/<nodeId>/content.md` — 文本节点内容
- `assets/<nodeId>/<参考图>` — 角色基准图 / 场景主视图拷贝

**`edges` 恒为空数组**。Toonflow 的 canvas Skill 明确「不通过编辑画布 JSON 绕过工具」——静态写出的边很可能与用户实际选择的模型能力不匹配，反而造成难以排查的半成品。连线由用户在 Toonflow 工作台内通过它的 Agent 完成。

**画布文件的识别条件**（上游 `apps/web/src/pages/workspace/canvasFile.ts` 的 `isCanvasFile`）：根对象首字段必须是 `"toonflowCanvas": true`。所以它必须排在 JSON 的第一个——放在 `nodes` 后面就只走完整解析分支，文件头读取（4096 字节）阶段认不出来，工作台不会把它当画布。

**节点 id 确定性派生**：`sha1(seriesId:episodeId:kind:localId)` → `v8-<kind>-<12 位>`。节点 id 同时是 `assets/<nodeId>/` 的目录名，随机 id 会让重复导出留下孤儿素材目录。同 id 重复导出是覆盖，不是堆积。id 只含小写字母、数字与连字符，满足上游对节点名的字符限制（禁用 `<>:"/\|?*`、不能以 `.` 或空格结尾）。

写文件用原子写（`.tmp` + rename），不留临时残留。

### 导回（Toonflow → 工坊）

面板在工具页中部。选好剧集与集后点「扫描新视频」，系统扫描 `workspaces/<series-id>/assets/` 下的 `.mp4` / `.mov` / `.webm`，勾选后「归集选中」**复制**到当前集的 `segments/`（片段级）或 `clips/`（分镜级）。

**复制而非移动**：Toonflow 工作区的原文件保持不动——用户可能仍在 Toonflow 内继续使用它。

**扫描的时间界桩**：取「本面板最后一次成功导出的时刻」，不是「最近 N 分钟」。用户隔天回来归集时成品不会被漏掉，同时别处的旧文件也不会被误列。

**写回规则**：勾选的文件按分镜顺序依次填入**还没有成片**的片段（或分镜），同时把状态推到 `done`。已有成片的片段不会被覆盖。视频比片段多时，多出的文件仍复制到目录，但在界面上明确报告「未关联到分镜」——不静默丢弃。

**未选中目标集时不猜**：没选剧集/集时，导出、扫描、归集三个按钮全部禁用，并显示「本工具不猜测目标集」。容器未运行时同样禁用（工作区归容器管，容器不在时导出的东西打不开）。

---

## 8. 启动序列

```
1. 定位工程目录（区分「目录不存在」与「缺 Dockerfile/compose.yaml」）
2. docker info 探活           → 不可达：提示去启动 Docker Desktop
3. 端口预检（ServerSocket.bind）→ 被占用：提示去改端口
       （在 up -d 之前做：compose 绑定失败会留下半启动状态）
4. 生成 override（端口 + bind mount + user 对齐）
5. docker compose ... up -d   → no such image：转「请先构建镜像」
6. 健康探测（60s 预算）
```

任一步失败都留下可读原因与可操作提示，不会白屏也不会假装成功。

### 构建失败分类

按输出特征归类，每类给不同的用户动作：

| 类别 | 用户动作 |
|---|---|
| 镜像源不可达（403 / `failed to resolve source metadata`） | 改 Docker Desktop 镜像源 |
| 锁文件不匹配（`--frozen-lockfile`） | 更新 Toonflow 仓库或去掉 frozen 构建 |
| 网络超时（TLS / `dial tcp` / `i/o timeout`） | 检查网络后重试（有缓存会快） |
| Docker 守护进程不可达 | 启动 Docker Desktop |
| 工程目录不对 | 改配置卡里的工程目录 |
| 未知 | 附完整日志尾部 |

**镜像源类必须排在宽泛网络类之前**：`tls handshake timeout` 会把一切网络问题都判成普通超时，而「镜像源不可达」的用户动作完全不同。

---

## 9. 退出时行为

默认**退出即停**（`stopOnAppExit: true`）。`runShutdownCleanup()` 会调 `disposeOnExit()`，只执行 `docker compose down`，**绝不动数据卷**——bind mount 下的工作区、素材与 `settings.json` 全部留在宿主机上。

清理抛异常时仍然退出：信号方已要求进程终止，卡在清理上会让子进程继续存活，比放弃清理更糟。

---

## 10. 端口

| 端口 | 用途 |
|---|---|
| 3177 | Toonflow 工作台（默认，只绑 `127.0.0.1`） |
| 8787 / 8788 | ARTEX 引擎（另一个工具，互不干扰） |
| 8797 | 本地词典桥 |

3177 是 spike 实测「本机最空」的值，与上面两者都不相邻，误记率低。

---

## 11. 许可边界

Toonflow 本体是 **MIT License**。本工具不 fork、不修改它的任何源码，只通过它自己提供的 Compose 工程启动它、通过它的 HTTP API 探活、通过 bind mount 与它交换文件。使用 Toonflow 生成的素材需遵守你自己与各模型供应商之间的条款，与本软件无关。
