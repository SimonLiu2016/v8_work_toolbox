# 无限画布

通过 Docker 在本地跑[无限画布](https://github.com/SimonLiu2016/infinite-canvas)的工作台，并把它与「AI 短视频工坊」用一条资产桥连起来。本工具**不实现任何无限画布创作能力**——它负责容器生命周期与资产互传；创作在无限画布自己的工作台里完成，用你自己在浏览器里配置的渠道与密钥。

> 变更来源：`openspec/changes/replace-toonflow-studio-with-infinite-canvas/`。
> 本文档取代已删除的 `docs/toonflow_studio.md`。

---

## 1. 运行前提

| 依赖 | 说明 |
|---|---|
| Docker Desktop | 必须已安装**且正在运行**。页面上的「Docker Desktop」按钮可直接拉起 |
| Compose v2 | `docker compose`（子命令形式）。Docker Desktop 29.x 自带 |
| 无限画布仓库 | 本地一份 checkout，需含 `Dockerfile` 与 compose 文件。默认路径 `/Users/simon/Workspace/github/infinite-canvas`，可在配置卡里改 |
| 端口 | 工作台默认 `3177`、资产桥默认 `8798`，都只绑 `127.0.0.1` |

**不需要本地构建**。上游 `docker-compose.yml` 引用 `ghcr.io` 上已发布的 amd64 + arm64 双架构镜像，点「启动」时 compose 自己会拉。只有要跑你本地改过的代码时才需要点「构建镜像」。

### 为什么端口必须只绑回环

上游 compose 的默认写法是 `"3000:3000"`，绑到全部网卡——等于把工作台暴露给同局域网的所有人。而工作台的 API Key、画布、素材全存在那个浏览器的本地存储里。本工具生成的 override 把端口覆盖成 `127.0.0.1:<配置端口>:3000`。

---

## 2. 架构与职责切分

```
┌──────────────────────── V8WorkToolbox ───────────────────────┐
│  AI 短视频工坊（剧集 / 分镜 / 角色卡 / 场景卡 / 片段）        │
│            ▲                                    │           │
│            │ POST /api/import                    │ GET       │
│            │ （视频字节）                         │ /api/*    │
│  ┌─────────┴──────────────┐                      ▼           │
│  │ 资产桥 loopback 服务   │◄────── HTTP ────── 画布插件       │
│  │ 127.0.0.1:8798         │                      │           │
│  └─────────┬──────────────┘                      │           │
│            │ 读写剧集数据                        │           │
│            ▼                                     │           │
│  StudioProjectManager                            │           │
└────────────┼──────────────────────────────────────┼──────────┘
             │ override（回环端口）                  │ 浏览器打开
             ▼                                       ▼
┌──────────────────── 无限画布容器 ────────────────────────────┐
│  nginx:1.27-alpine + Vite 静态产物                          │
│  没有任何业务 API，没有任何数据卷                            │
└──────────────────────────────────────────────────────────────┘
                              ▲
                              │ 浏览器直连用户自己配置的接口
                              │ （密钥、画布、素材全在 IndexedDB）
```

| 组件 | 职责 | 明确**不做**的事 |
|---|---|---|
| `InfiniteCanvasComposeService` | 探活、双端口预检、`up -d`、健康探测、`stop` | 不实现任何无限画布业务能力 |
| `InfiniteCanvasImageBuildService` | `docker compose build` 单飞 + 流式日志 + 失败分类 | 不改上游 `Dockerfile` |
| `InfiniteCanvasOverrideStore` | 生成/重写 `docker-compose.v8box.yml` | 不改上游 compose 文件 |
| `InfiniteCanvasBridgeServer` | 签发插件、选集列表、导出载荷、参考图原图、接收归集视频 | 不持有、不转发任何 API Key |
| `InfiniteCanvasAssetBridge` | 渲染节点载荷、按分镜顺序归集 | 不写连线、不写生成状态、不碰模型配置 |
| `InfiniteCanvasConfigStore` | `config/infinite-canvas.json` 薄封装 | 不存任何密钥 |

### 与 Toonflow 版的根本差异

Toonflow 是一个有服务端数据目录的真后端，资产桥整条建立在 bind mount 上。无限画布的 docker 镜像**只是 nginx 静态服务器**——密钥、画布、素材与生成记录全在浏览器本地（localforage / IndexedDB），宿主机文件系统上一个字节都没有。所以：

- 没有 `toonflow_data/` 那样的数据目录，也没有 bind mount 与 `user:` 对齐；
- 健康探针判据**反过来**：Toonflow 要「必须是业务接口的 JSON 信封」，这里要「必须是这个容器独有的入口页形态」；
- 资产桥改走 loopback HTTP + 画布插件。

---

## 3. 健康就绪判定为什么反过来

无限画布只有静态资源，nginx 的 `try_files $uri $uri/ /index.html` 对任意路径都返回 200 的 `index.html`。只看状态码会把「宿主机另一个进程占了这个端口」误判成「无限画布已就绪」，把用户送到一个打不开的工作台。

判据要求响应体**同时**含两项标识：

| 标识 | 证明什么 |
|---|---|
| `<div id="root">` | 是 SPA 入口页，而不是任意 200 |
| `<script src="/config.js">` | 是**我们这个容器**的 nginx（`/config.js` 由容器 entrypoint 生成、入口页固定引用），且 entrypoint 已执行完 |

第二条顺带解决「entrypoint 还没跑完就打开工作台会缺运行时配置」的问题。就绪预算 15 秒（Toonflow 版是 60 秒——那个预算要覆盖容器首次启动的插件初始化，静态服务不需要）。

---

## 4. 资产桥：装一次插件，双向都不经过目录

无限画布的插件系统支持「按 URL 安装」，而 V8 已经在跑 loopback 服务，所以插件挂在同一个服务上：**装一次即由无限画布自己记住**，重启浏览器不用重装。

### 安装

1. 打开本工具页的「安装画布插件」卡片，复制插件地址与资产桥密钥；
2. 在无限画布的节点插件面板里「按 URL 安装」，填入地址；
3. 首次使用时插件会要密钥（之后存在浏览器 localStorage）。

### 导入到画布（在插件的面板里操作）

插件面板有剧集与集两个下拉（design D11：选集和触发都在画布侧，V8 侧再放一份就是两个真相来源）。选定后点「导入到画布」：

```
GET /api/episodes                剧集 + 集列表
GET /api/export?seriesId&episodeId   节点载荷
GET /assets/<seriesId>/<...>      参考图原图
```

图片节点不携带 base64 数据，只给 `http://127.0.0.1:8798/assets/...` 这样的 URL。插件调无限画布自己的 `uploadImage(url)`——它内部走 `fetch()`，会把图拉进浏览器的 IndexedDB 并返回 storageKey。一集角色卡 + 场景卡的参考图轻松上几十 MB，base64 会再涨 33% 并把页面卡死。

节点 id 由 `sha1(seriesId:episodeId:kind:localId)` 派生，所以**重复导入是幂等的**——第二次命中同一批 id 走 `update_node`，不会在画布上堆出第二套。

### 归集成片（也在插件面板里操作）

勾选画布上的视频节点 → 点「归集到工坊」。插件把每个节点的 `metadata.v8`（本工具写入的结构化标识）与视频 Blob 一起 POST 回来：

```
POST /api/import?seriesId&episodeId&fileName&targetIsSegment
```

**目标集来自节点自身，不需要另外选**。这也让「未选目标集时要不要猜」这个问题不存在——用户手工建的节点没有 `metadata.v8`，插件会明确报告它无法配对并跳过，不猜。

V8 侧收到字节后先落 `infinite_canvas/inbox/`，工具页的资产桥面板列出待归集文件，点「归集到工坊」时按分镜顺序填进还没有 `clipPath` 的片段/分镜，并把状态推到 done。**复制而非移动**——画布上的原节点不动，你可能还在用它。

---

## 5. 密钥边界

无限画布的密钥只存在浏览器本地。生成请求由无限画布直连你自己配置的渠道，**不经过 V8**——V8 侧传输通道上流过的数据不含任何 API Key、渠道地址或 WebDAV 凭据。

另外一条边界：无限画布的配置文件 `infinite-canvas-config.json` **明文明文保存 API Key 与 WebDAV 密码**（上游文档原话「不应公开分享」）。本工具**显式拒绝**把它当作导入源——用户很可能在整理目录时把它和画布导出文件摆在一起，静默跳过会让用户以为导入了。

资产桥自己的密钥是另一回事：它只听 `127.0.0.1`，密钥拦的是误用与机会主义调用，不是已能读本地文件的攻击者。

---

## 6. override 文件

文件名是 `docker-compose.v8box.yml`，**不是** `docker-compose.override.yml`——compose 会在用户手敲 `docker compose up` 时隐式自动加载后者，而我们的命令又显式 `-f` 了它一次。用独立文件名让「本工具管理」与「用户手动」完全分离。

只做两件事：

```yaml
# Generated by V8WorkToolbox infinite canvas tool
services:
  app:
    image: ghcr.io/basketikun/infinite-canvas:latest   # 本地构建时才覆盖
    ports: !override
      - "127.0.0.1:3177:3000"
```

`!override` 标签必须带：compose 对 `ports` 的默认合并行为是追加，不带会导致 3000 同时绑两个端口（上游的 `"3000:3000"` 还在）。

非本工具生成的文件（以标记注释首行识别）会先备份到 `~/Library/Application Support/V8WorkToolbox/infinite_canvas/` 再覆盖，且 UI 会告知用户发生了备份。

---

## 7. 端口

| 端口 | 用途 |
|---|---|
| `3177` | 无限画布工作台（宿主机侧） |
| `8798` | 资产桥 loopback 服务 |

已占用：ARTEX `8787` / `8788`、本地词典桥 `8797`。两个端口都在启动前预检，冲突时报端口号并允许改端口重试。

---

## 8. 失败分类

| 类别 | 用户动作 |
|---|---|
| Docker 未运行 | 启动 Docker Desktop 等它完全就绪 |
| 端口被占用 | 改端口后重试 |
| Compose 服务名不匹配 | 打开上游 compose 文件核对 `services` 下的名字（上游改名时 override 会静默失效，要到 `up` 时才炸） |
| 镜像未拉取 | 检查网络或 Docker 镜像源；要本地代码才点「构建镜像」 |
| 服务未就绪 | 看附带的容器日志尾部 |

---

## 9. 本地镜像与插件 SDK

插件依赖无限画布的 TypeScript 插件 SDK（`CanvasPlugin` / `CanvasPluginAi` / `CanvasNodeDefinition`）。上游 `git pull` 导致 SDK 变化时插件会加载失败——插件声明了 `minAppVersion`，V8 侧的「安装画布插件」卡片也会显示「尚未检测到插件连接」。

### 参考图入库需要本地镜像

插件的参考图入库走宿主的 `ctx.ai.uploadReference`。这个成员**不在上游原版 SDK 里**——它是本仓库的 fork 加的（`web/src/types/canvas-plugin.ts` + `web/src/pages/canvas/hooks/use-plugin-host.tsx`）。所以：

| 镜像来源 | 参考图能否入库 |
|---|---|
| ghcr.io 发布版（默认） | 不能。插件会明确提示「当前无限画布版本不支持参考图入库」，文本节点正常，图片节点缺图 |
| 本地构建 `infinite-canvas:local` | 能 |

用本地镜像的步骤：

```bash
cd ~/Workspace/github/infinite-canvas
docker build -t infinite-canvas:local .
```

然后在工具页配置卡打开「用本地构建的镜像」开关并保存。override 会覆盖 `image:` 指向 `infinite-canvas:local`。

**别忘了先构建再启动**——开关打开而本地没有那个 tag，启动会报「镜像未拉取」。

### 降级路径

即使宿主没有 `uploadReference`，插件也不会崩：它会退回 data URL 让画布自己 `uploadImage`（`hydrateCanvasImages` 对 `data:image/` 的处理），代价是参考图要挤进 JSON、慢一些。这条路径当前用不到（本地镜像已通），留着是为了万一将来 fork 落后于上游。

插件源码内嵌在 `lib/tools/infinite_canvas/services/infinite_canvas_canvas_plugin_source.dart`，SDK 变化时照着改那段 JS。
