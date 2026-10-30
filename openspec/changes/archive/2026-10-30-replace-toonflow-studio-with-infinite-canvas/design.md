# 设计：用无限画布替换 Toonflow 漫剧工坊

> 动机与范围见 `proposal.md`。本文件只记录**怎么做**与**为什么这样做**，需求契约见 `specs/`。

## Context

被替换的对象是一套已经跑通的 Docker 托管工具（`lib/tools/toonflow_studio/`，3231 行 + 1589 行测试），它的资产桥整条建立在「Toonflow 是有服务端数据目录的真后端」这个前提上：

```
V8 写画布 JSON 到磁盘 ──► bind mount ──► 容器内 Toonflow 读
容器内 Toonflow 生成视频落盘 ──► bind mount ──► V8 扫 assets/*.mp4
```

无限画布把这个前提抽掉了。它的 docker 镜像只有 nginx + Vite 静态产物，没有业务 API、没有数据卷；密钥、画布、素材、生成记录全在浏览器本地（localforage：`app_state` / `canvas_store` / `ai_config_store` / `image_files` / `media_files`）。因此**不存在任何可供 bind mount 的路径**，资产桥必须换传输通道。

同时，无限画布暴露了两个可用的接缝：

1. **节点插件 SDK**（`web/src/types/canvas-plugin.ts`）：`CanvasPlugin` / `CanvasNodeDefinition` / `CanvasPluginHost` / `CanvasPluginAi`，插件经 URL 动态安装并持久化，可用 `applyOps` 操作画布、用宿主已配渠道调 `ai.generateVideo`；
2. **上传入口**（`uploadImage` / `uploadMediaFile`）：接受 URL 或 Blob，写入 IndexedDB 并返回 `storageKey`。`uploadImage` 内部走 `fetch(withLocalProxy(url))`，因此**它会把一个 `http://127.0.0.1:<port>/...` 当作普通远程图片拉取并入库**——这正是参考图进画布的通路。

## Goals / Non-Goals

**Goals**

- Docker 生命周期部分改造沿用，不重写：端口预检、override、失败分类、退出处置这些已验证的行为保留。
- 资产桥换成「loopback HTTP 服务 + 画布插件」，双向都不经过共享目录。
- 密钥不离开浏览器：生成请求由无限画布直连用户配置的渠道。
- 「Toonflow」这个名字从代码、配置键、路径、spec、文档中全部消失。

**Non-Goals**

- 不改无限画布上游仓库一行代码。插件从 V8 的 loopback 服务签发，fork 保持与上游可合并。
- 不实现 ZIP 文件接力作为兜底路径。评估过：回程要靠节点标题文本配对，脆且每轮往返要用户做两次文件选择；loopback 方案跑通后没有保留它的理由。
- 不让 V8 代替无限画布持有或转发 API Key。
- 不把无限画布的画布数据同步回 V8（V8 只要成片，不要画布结构）。

## Decisions

### D1：传输通道 = loopback HTTP 服务 + 插件，不用共享目录

```
┌──────────────── 无限画布页面（浏览器）────────────────┐
│  画布节点插件（由 V8 签发，URL 安装一次）            │
│    GET  /v8-plugin.js                     安装      │
│    GET  /api/episodes                     选集列表  │
│    GET  /api/export?seriesId&episodeId    导出载荷  │
│    GET  /assets/<path>                    参考图原图│
│    POST /api/import?...                  回传成片  │
└───────────────────────┬──────────────────────────────┘
                        │ 只听 127.0.0.1，CORS 放开
                        ▼
┌──────────────── V8 资产桥服务 ──────────────────────┐
│  dart:io HttpServer（沿用 LocalDictionaryBridge 范式）│
│    ├─ /v8-plugin.js    内嵌的插件 JS 源码            │
│    ├─ /api/episodes    剧集+集列表                   │
│    ├─ /api/export      渲染节点载荷（含参考图 URL）   │
│    ├─ /assets/*        工坊参考图原图                │
│    └─ /api/import      收视频 Blob → segments/clips │
└───────────────────────┬──────────────────────────────┘
                        ▼
              StudioProjectManager（剧集数据）
```

**为什么不用 ZIP 接力**：无限画布的原生导入格式是 `projects.json` + `projects/<id>/files/<storageKey>.<ext>` 的 ZIP，V8 侧用已有的 `package:archive` 完全能生成。但回程（画布 → V8）没有对应的原生入口——用户只能「导出选中节点」拿到一个 ZIP，再由 V8 解析并按**节点标题**猜哪个视频对应哪个分镜。猜错就是静默的张冠李戴。loopback 方案的回程带结构化元数据，不需要猜。

**为什么不让 V8 反向推（WebSocket/SSE）**：导出方向让插件**拉取**而不是 V8 推送，服务端就是无状态的查询端点，没有连接生命周期、没有「命令发出去了但页面没收到」的丢失问题，插件重试即幂等（节点 id 确定性派生）。回程本来就是浏览器发起。

**为什么复用 `LocalDictionaryBridge` 的范式**：项目里已经有一个只听回环、自己写 CORS 头、端口冲突 fail-soft、可注入测试的 `HttpServer`。新服务与它同构，审阅成本低。

**备选**：走无限画布内置的 WebDAV 同步（它同步 canvas/assets/生图记录/视频记录 4 个域）。否掉——用户仍要在浏览器里填一套 WebDAV 配置再点「立即同步」，操作量与 ZIP 方案相当，却要多撑一层同步/合并/清单机制，而且它同步的是画布全量数据而非「这一集的成片」。

### D2：参考图经 loopback URL 进 IndexedDB，不 base64 内联

导出载荷里的图片节点不携带图片数据，只携带 `http://127.0.0.1:<port>/assets/<seriesId>/<file>`。插件拿到 URL 后调 `uploadImage(url)`：

- `uploadImage` 内部 `fetch(withLocalProxy(url))`——本地代理默认关闭，关闭时 `withLocalProxy` 原样返回 URL，所以请求直达 V8；
- 返回 `{ url, storageKey }`，插件据此建节点：`metadata.content = uploaded.url`、`metadata.storageKey = uploaded.storageKey`；
- 之后 `hydrateCanvasImages` 会按 `storageKey` 正确还原，节点也能被拖进其他节点当参考图用（`resolveCanvasReferenceImages` 走 `imageToDataUrl({storageKey})`）。

**V8 侧必须为 `/assets/*` 写 `Access-Control-Allow-Origin`**，否则浏览器跨源拉取被拒。词典桥已经这么做，抄它的响应头写法。

**为什么不让 V8 把图片 base64 进载荷**：一集角色卡 + 场景卡的参考图轻松上几十 MB，base64 再涨 33%，JSON 解析会把页面卡死。分两次传输（先小 JSON，再按需拉图）还能让「先看到画布结构」早于「图片加载完」。

**回程同理**：视频 Blob 用请求体原样 POST，不 base64。V8 侧流式落盘。

### D3：导出载荷由 V8 渲染，插件只负责 applyOps

V8 的 `/api/export` 返回一个描述性载荷：

```json
{
  "seriesId": "…", "episodeId": "…", "episodeIndex": 3,
  "nodes": [
    { "kind": "text",  "id": "v8-<sha1>", "title": "世界观与风格", "markdown": "…" },
    { "kind": "text",  "id": "v8-<sha1>", "title": "第3集剧本与分镜", "markdown": "…" },
    { "kind": "image", "id": "v8-<sha1>", "title": "角色 · 林拓",
      "prompt": "…", "negativePrompt": "…", "imageUrl": "http://127.0.0.1:8798/assets/…" }
  ],
  "layout": { "columns": 3, "gapX": 96, "gapY": 160 }
}
```

插件把它翻译成 `applyOps([{type:"add_node", id, nodeType:"text"|"image", title, position, metadata}, …])`。已存在的 id 走 `update_node` 而不是重复 add。

**为什么分工如此**：spec 的权限边界是「只写内容节点与其素材，不写连线、不写生成状态」。把「哪些节点」的决策留在 V8（它知道剧集结构），把「怎么落进画布」的决策留给插件（它知道 SDK 与节点规格），两边都不越界。插件里不出现任何剧集业务逻辑。

**幂等**：节点 id 由 `sha1(seriesId:episodeId:kind:localId)` 派生，重复导出命中同一批 id。这直接复用了原资产桥的 `_nodeId` 设计，只是消费方从「写 JSON」变成「applyOps 的 id 参数」。

**布局**：V8 给列数/间距建议，插件负责排版。原桥把所有节点堆在 `{x:0,y:0}`，那是因为 Toonflow 自己会重排；无限画布不会，堆在一处会让用户第一眼看到一坨叠起来的节点。

### D4：配对靠节点元数据，不靠标题文本

插件建节点时把 V8 的标识写进 `metadata.v8`：

```json
{ "v8": { "seriesId": "…", "episodeId": "…", "entityKind": "shot", "entityId": "7" } }
```

回程时插件把选中视频节点的 `metadata.v8` 原样 POST 回来，V8 直接定位目标分镜/片段。

**为什么不用标题**：标题是给人看的，用户会改。原桥的 Toonflow 侧回程靠扫文件 mtime，没有这个问题；换成浏览器存储后文件系统不可见，只能靠节点自身携带的标识。`metadata` 是开放字典（`CanvasNodeMetadata` 有 `[key: string]: unknown` 形态的扩展位），塞自定义键不影响宿主。

### D5：健康探针判据反转

Toonflow 的判据是「必须校验业务接口的 JSON 信封」，因为它的 API 与静态资源同进程，任意路径都会返 200 HTML。无限画布**只有**静态资源，nginx 的 `try_files $uri $uri/ /index.html` 对任意路径都回 `index.html`。所以判据反转为「响应体必须含这个容器独有的两个标识」：

| 标识 | 证明什么 |
|---|---|
| `<div id="root">` | 是 SPA 入口页而不是任意 200 |
| `<script src="/config.js">` | 是**我们这个容器**的 nginx（`/config.js` 由 `web/docker-entrypoint.sh` 生成，上游 index.html 固定引用它），且 entrypoint 已执行完 |

第二条同时解决了「宿主机另一个进程占了这个端口」的误判——那种服务不会恰好返回引用 `/config.js` 的页面。就绪预算从 60 秒降到 15 秒：60 秒的理由原本是 Toonflow 首次启动要做插件初始化，静态服务起来是毫秒级。

### D6：override 只剩端口回环 + 镜像覆盖

上游 `compose.yaml` 实际是 `docker-compose.yml`，服务名 `app`，`ports: ["3000:3000"]`——**绑全部网卡**。override 做两件事：

```yaml
# Generated by V8WorkToolbox infinite canvas tool
services:
  app:
    image: ghcr.io/basketikun/infinite-canvas:latest   # 可被本地构建覆盖
    ports: !override
      - "127.0.0.1:3177:3000"
```

删掉 Toonflow 版 override 的 `user: "<uid>:<gid>"` 与 bind mount：nginx 不写盘，这两项在这里是无意义噪音，留着只会让读者以为这里有个数据目录。

`!override` 标签必须带——compose 对 `ports` 的默认合并行为是追加，不带会导致 3000 同时绑两个端口。这条从原实现照搬（原实现的踩坑记录见 `docs/toonflow_studio.md` 与 archive 里的 design）。

**override 文件名改为 `docker-compose.v8box.yml`**，不复用 `docker-compose.override.yml`：compose 会在用户手敲 `docker compose up` 时**隐式自动加载**后者，而我们的命令又显式 `-f` 了它一次，同一文件被传两遍的行为我不打算依赖。用独立文件名让「本工具管理」与「用户手动」完全分离。

**compose 文件名要回传**：`locateProject` 现在返回它实际命中的那个文件名（`compose.yaml` / `compose.yml` / `docker-compose.yml`），因为 `-f` 参数与 override 都必须与它对齐。上游给的是 `docker-compose.yml`，这是硬事实。

**服务名 `app` 提成常量**。上游改名时 compose 不会因为 override 引用不存在的服务而报错，`up` 时才炸——沿用原工具的「Compose 服务名不匹配」失败分类，让用户去核对而不是盲目重试。

### D7：镜像入口降级为「拉取为主，构建可选」

上游 `docker-compose.yml` 直接引用 `ghcr.io/basketikun/infinite-canvas:latest`（CI 出 amd64 + arm64 双架构）。所以：

- 默认路径就是 `up -d`，compose 自己拉镜像。**不需要「先构建再启动」**。
- 「构建镜像」按钮保留，但语义变成「用本地代码构建」——只在用户改过 `web/` 或要试未发布改动时才需要。它对应上游的 `docker-compose.local.yml` 那条路。
- 构建失败分类表删掉 Toonflow 特有的 bun 锁文件条目（`frozen-lockfile` / `lockfile had changes`），增加「构建上下文缺失」（本地没有仓库时点构建）。

「镜像未拉取」的失败分类保留：`Unable to find image` / `pull access denied` 归为一类，用户动作是检查网络/镜像源，而不是重试启动。

### D8：密钥边界的对象换成上游配置文件

原 spec 的边界是「绝不读写 `toonflow_data/settings.json`」。新边界是「绝不读取无限画布的配置文件」——`infinite-canvas-config.json`（`web/src/services/config-file.ts`）明文含 `config.apiKey`、各渠道 `apiKey`、`webdav.password`，上游文档原话「配置文件包含 API Key 和 WebDAV 凭据，不应公开分享」。

**新边界比旧的更危险**：`settings.json` 在 `toonflow_data/` 里，是工具的私有目录，用户不会往里放别的东西；而配置文件是用户会随手导出、随手放在下载目录的东西。整理目录时把它和画布导出 ZIP 摆在一起是很自然的动作。所以 spec 要求**显式拒绝**而不是忽略——静默跳过会让用户以为导入了。

这条边界在 loopback 架构下反而更容易守：V8 侧的 `/assets/*` 只服务工坊自己的目录，根本不具备读浏览器存储的能力；要违反它只能靠用户主动把文件递进来。

### D9：彻底改名，不做兼容层

`toonflow` → `infinite-canvas` 的改名覆盖：tool id 常量、`config/toonflow-studio.json` → `config/infinite-canvas.json`、`AppPaths.toonflowDir` / `toonflowDataDir`（直接删，不保留 deprecated getter）、`lib/tools/toonflow_studio/` → `lib/tools/infinite_canvas/`、两个 spec 目录、`docs/`、测试目录、`frequently_used_tools_test.dart` 的 id 断言。

**为什么不做配置迁移**：旧配置只有 5 个平凡字段（工程目录/端口/退出即停/镜像站/自动启动），其中「bun 镜像站」随 Toonflow 的构建路径一起作废。用户重设一次的成本低于维护一条迁移代码路径，而且旧配置留着会让人以为还支持 Toonflow。

**为什么不保留旧工具作为备选**：用户明确说「一点都不好用」且要求全部移除。两个 Docker 工具并存还会让端口预检表、退出处置、spec 目录都翻倍。

### D10：端口分配

| 端口 | 用途 | 依据 |
|---|---|---|
| `3177` | 无限画布工作台（宿主机侧） | 复用原工具的 spike 结论：3000/8787/8797/3177 中它最空 |
| `8798` | 资产桥 loopback 服务 | 已占用：ARTEX 8787/8788、词典桥 8797。取相邻空值 |

两个端口都要能检测占用并报可读原因，但**检测责任不同**：

- 工作台端口归 compose 启动流程的预检——它在 `up -d` 之前做，因为 compose 的绑定失败会留下半启动状态且错误信息难读；
- 资产桥端口归 `InfiniteCanvasBridgeServer.start()` 自己的 `HttpServer.bind`——那个端口由本进程持有，**不能**进 compose 的预检集合，否则只要工具页打开过（bridge 已起），点启动就必然失败在「端口被占用」上，而占用者正是自己人。

> 2026-10-16 实测踩到：资产桥端口曾被一并列入 compose 预检，表现为「点启动即失败：端口 8798 被占用」，而 `lsof` 显示占用者就是 V8 自己。修正后预检只覆盖工作台端口，并补了回归测试。

## Risks / Trade-offs

**[上游 SDK 漂移导致插件失效]** → 插件声明 `minAppVersion`；加载失败时在 V8 工具的资产桥面板上可见（插件安装后由 V8 记录安装态，心跳/握手失败即标红），而不是只出现在无限画布的 console 里。用户在无限画布里点「更新插件」时，V8 侧要能报告新签发的插件版本。

**[`/config.js` 判据随上游改版失效]** → 判据做成可配置的两段式（挂载点 + 脚本标识），并在工具页明示「当前判据来自上游 index.html 的形态」。上游若改判据，失败表现是「启动超时」而非「误判就绪」——超时会附容器日志，方向上安全。

**[视频经 HTTP 回传大文件超时/中断]** → 请求体原样传输（无 base64 膨胀），V8 侧流式写入 `.part` 文件，完成后 rename；超时后清理残留 `.part` 并在结果中报告失败节点。单文件上限设为一个明确数值（初定 512 MB），超限在插件侧就拒绝并说明，不浪费带宽。

**[loopback 服务被本机其他进程调用]** → 只听 `127.0.0.1` + 一个安装时生成的共享密钥（请求头带）。与词典桥同构：密钥拦的是误用与机会主义调用，不是已能读本地文件的攻击者。密钥在插件安装时由 V8 写进插件源码，不进浏览器持久化存储之外的地方。

**[用户在画布里改了导出的节点标题/删了节点]** → 导出是幂等的按 id upsert，标题被改不影响（applyOps 只更新 metadata 不覆盖 title）；节点被删则下次导出重建。回程若选中节点已无 `metadata.v8`，报告「无法配对」并列出该节点，不猜。

**[无限画布首次打开是空的，用户不知道该装插件]** → 工具页给「安装画布插件」卡片：显示插件 URL、一键复制、以及「安装后画布上会出现 V8 面板」的说明。安装状态由 V8 记录并在心跳时更新。

**[compose 服务名/文件名上游变更]** → 服务名提常量 + 失败分类（D6）；compose 文件名运行时探测（D6）。

## Migration Plan

1. 新增 `lib/tools/infinite_canvas/` 与 `test/tools/infinite_canvas/`，与旧工具并存期不短——但旧工具在本变更内一并删除，所以实际是「先建新的、跑通、删旧的」。
2. 删 `lib/tools/toonflow_studio/` 与 `test/tools/toonflow_studio/`。
3. 删 `AppPaths.toonflowDir` / `toonflowDataDir` 及 `ensureDirs` 登记；同步 `test/app_paths_test.dart`。
4. 改 `main.dart` 退出处置、`registry.dart`、`tool_definition.dart`、`frequently_used_tools_test.dart`。
5. 删 `docs/toonflow_studio.md`，写 `docs/infinite_canvas.md`。
6. 归档本 change 时把 `specs/infinite-canvas-studio/` 与 `specs/infinite-canvas-bridge/` 落成正式 spec，删除 `openspec/specs/toonflow-studio/` 与 `toonflow-asset-bridge/`。
7. `frequently_used_tools_test.dart` 的 AI 分类断言同步为替换后的集合（历史上 `ai-video-studio` 与 `novel-manager` 接入时都漏改过这条，注释里有记录）。

**回滚**：本变更内是单向的（删旧建新）。回滚即 `git revert` 整个 change 的提交；旧配置键 `config/toonflow-studio.json` 不会被新代码读取，也不会被删除，revert 后原样可用。

### D11：选集与触发的落点全在插件面板，V8 面板只做状态与报告

选集和两个动作的触发都在画布侧的插件面板里，V8 的工具页面只承担状态与报告：

| 动作 | 在哪触发 | 目标从哪来 |
|---|---|---|
| 导入画布 | 插件面板 | 插件面板的剧集 + 集下拉 |
| 归集成片 | 插件面板 | **选中视频节点自身的 `metadata.v8`**——不需要额外选择 |
| 导出报告 / 安装状态 / 服务心跳 | V8 工具页 | 资产桥服务的运行态 |

**为什么导入在插件面板**：导入的结果落在画布上，用户此刻正看着画布。回 V8 窗口选集再回画布看结果，是两次上下文切换，而且 V8 选集后用户可能又去翻别的画布——「当前选中」这个隐式状态在两头之间没有可靠的同步点。插件面板里下拉是显式的，导入动作与它的结果在同一视野内。

**为什么归集反而更简单**：用户是在画布上选中刚生成的视频节点，节点自己带着 `metadata.v8`（`seriesId` / `episodeId` / `entityKind` / `entityId`）。插件把这些原样 POST 回来，V8 直接定位——归集路径上**不存在「选目标集」这个步骤**，也就不存在「用户忘了选、V8 要不要猜」的问题。spec 里「未选择集时不猜测目标」那条由这条兜住：目标永远来自节点自身。

**V8 面板剩什么**：容器状态、构建入口、失败卡、日志（第 2/3 组），加上资产桥的服务状态、插件 URL 与复制按钮、最近一次导入/归集的报告。它不再需要剧集下拉——那个下拉搬到插件面板后，V8 侧多一份就是两个真相来源。

### D12：不做「打开工具时自动启动容器」

原工具有 `autoStartOnOpen` 配置，默认 false，且没有任何反馈要求打开它。新工具直接不实现这个配置项。

**为什么不留**：一个默认关闭、没人开、且开启后会让每次打开工具都触发一次 Docker 探活 + `up -d` 的开关，留着只是给配置界面增加一行噪音。真有人要，从 `stopOnAppExit` 的实现旁边加回来是十分钟的事；提前留着则要在 spec 里为它写场景、在测试里为它造一条启动路径。

**`stopOnAppExit` 保留**：它与自动启动不是一对。退出即停是安全默认值（不留孤儿容器占端口），且已经过验证。
