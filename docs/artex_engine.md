# ARTEX 渗透引擎（artex-engine）

AI 自主渗透测试平台，以 Docker 容器方式托管，本软件只负责启停与打开工作台。

> **仅用于授权的安全测试。** 引擎自身的每次高影响操作（exploit、爆破、注入利用）
> 都会在其 Web 工作台内要求人工确认。上游 ARTEX 采用 AGPL-3.0，见文末「许可边界」。

## 运行前提

| 依赖 | 要求 | 说明 |
| --- | --- | --- |
| Docker Desktop | 已安装且正在运行 | 未运行时会提示并提供跳转按钮 |
| ARTEX 仓库 | 默认 `~/Workspace/github/artex-ymh` | 可在工具界面修改，需含 `docker-compose.yml` |
| 镜像 `artex-ymh:local` | 首次需构建 | 约 9 分钟，1.67GB（2026-10-10 实测） |
| Docker Compose | ≥ 2.20 | override 用到 `!override` YAML 标签 |

首次使用三步：

```bash
# 1. 构建镜像（工具界面的「构建镜像」按钮即执行此命令）
cd ~/Workspace/github/artex-ymh
docker compose build \
  --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  --build-arg APT_MIRROR=mirrors.aliyun.com

# 2. 在工具界面点「启动」，等状态变为「运行中」

# 3. 点「打开工作台」——首次会要求设置访问密码
```

三个构建参数在工具界面可改。**它们管不到 chromium 下载**：`Dockerfile.source`
里的 `playwright install --with-deps chromium` 走 `playwright.azureedge.net`、
nodesource 走 `deb.nodesource.com`，这两个地址不受上述参数控制，需要 VPN/代理。
该步失败时工具会给出专项提示，且此前的构建层已缓存，重试不会从零开始。

## 架构

```
┌──────────────────────────────────────────────────────────┐
│  V8WorkToolbox (Flutter)                                  │
│                                                          │
│  ArtexEnginePage                                         │
│    ├── ArtexComposeService   容器启停 / 端口预检 / 健康探测│
│    ├── ArtexImageBuildService 镜像构建 / 失败诊断          │
│    ├── ArtexCaService          根 CA 三态 / 安装命令       │
│    ├── ArtexOverrideStore      docker-compose.override.yml│
│    └── ArtexConfigStore        SettingsStore 配置          │
└───────────────────────┬──────────────────────────────────┘
                        │ docker compose up -d / stop
                        ▼
┌──────────────────────────────────────────────────────────┐
│  Docker（你手动 build 一次，之后只启停）                    │
│  ┌────────────────┐        ┌──────────────────┐          │
│  │ artex (Go)     │───────▶│ postgres:16      │          │
│  │ :8787 API+UI   │        │ 49 张表          │          │
│  │ :8788 MITM 代理│        └──────────────────┘          │
│  └────────────────┘                                     │
└──────────────────────────────────────────────────────────┘
```

**职责切分**：本工具不实现任何渗透能力，也不内嵌引擎的任何代码。它只发号施令，
真正干活的是容器。因此工具用主窗口内嵌页面而非独立窗口——容器不随窗口生死。

## 两个必须了解的机制

### 1. 伪装门控必须关闭（`ARTEX_GATE=off`）

引擎内置的伪装门控是为公网服务器设计的：未过门控的请求一律返回逐字节固定的
假 nginx 欢迎页。它的判定依据是**进程内看到的监听地址**——容器里 `-addr :8787`
绑定的是 `0.0.0.0`，所以容器内的引擎认为自己暴露在公网，自动开启门控。

后果：`/api/health` 返回的是 **HTTP 200 的 HTML 页面**，不是引擎 JSON。任何只看
状态码的健康检查都会误判为「服务就绪」，然后把用户送到一个假页面前。

本工具的处置是双保险：

- **override 注入 `ARTEX_GATE: "off"`**（默认开启，工具界面可关）
- **健康探测校验响应体**：要求可解析 JSON 且含 `service` 字段。抓到欢迎页特征时
  给出「引擎被伪装门控拦截」的定向提示，而不是泛泛的超时

启动日志中出现 `[gate] ARTEX_GATE=off — 伪装门控已关闭` 即表示配置生效。

### 2. 运行时配置走 override，不改上游 compose 文件

本工具在工程目录生成 `docker-compose.override.yml`，承担两件事：注入
`ARTEX_GATE=off`、按配置覆盖端口。**不编辑上游 `docker-compose.yml`**——那样
`git pull` 一次就丢，且会让 artex 仓库出现本地未提交改动，干扰升级。

override 只写 `artex` 服务的差异段：

```yaml
services:
  artex:
    environment:
      ARTEX_GATE: "off"
    ports: !override
      - "127.0.0.1:8787:8787"
      - "127.0.0.1:8788:8788"
```

`!override` 标签**不能省**：compose 对 `ports` 的默认合并行为是追加，不带标签会
导致 8787 绑两次（上游的 `0.0.0.0:8787` 仍在）——既是端口冲突，也让引擎暴露在
所有接口上。实测对比：

```
带 !override    → 2 条端口，都只绑 127.0.0.1
不带 !override  → 3 条端口，其中一条是 0.0.0.0:8787
```

文件头部有固定标记注释。只有本工具生成的文件才会被重写；**手写过别的内容的
override 会先备份到 `AppPaths.artexDir`**（`~/Library/Application Support/
V8WorkToolbox/artex/`）再替换，不会静默冲掉。

## 数据位置

引擎数据**不在本软件的数据目录内**，归 Docker 与 ARTEX 仓库管理：

| 位置 | 内容 |
| --- | --- |
| docker 卷 `artex-ymh_pgdata` | PostgreSQL 全部数据（49 张表） |
| `<工程目录>/data` | 工作区、jwt.key、gate.key、traffic 录制树、`_ca` 根证书、`_auth` 代理口令 |
| `<工程目录>/docker-compose.override.yml` | 本工具生成的运行时配置 |
| `~/Library/Application Support/V8WorkToolbox/artex/` | 本工具自己的 override 备份 |

**删除本软件不会删除引擎数据**，备份时请把上表前两项一并考虑。反向也成立：
`docker volume rm artex-ymh_pgdata` 会清空全部渗透历史，本软件不会替你决定。

## 根证书

引擎的流量录制代理用自签根 CA 解密 HTTPS。证书路径
`<工程目录>/data/traffic/_ca/mitmproxy-ca-cert.pem`（引擎首次运行后生成）。

安装（需要 sudo，因为 `_ca` 目录被引擎置为 700/600）：

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/Workspace/github/artex-ymh/data/traffic/_ca/mitmproxy-ca-cert.pem
```

工具界面会在检测到「已生成未安装」时展示这条命令与一键复制。**它绝不自动执行**——
装进 System.keychain 后对全系统生效，是系统级副作用。

卸载：打开「钥匙串访问」→ 系统 → 证书，删除 mitmproxy 相关条目。删除证书文件
本身不会撤回信任。

流量代理默认带口令（`<工程目录>/data/traffic/_auth`，0600）。要让它代理你的
浏览器，需把系统代理设为 `127.0.0.1:8788` 并在提示时输入该文件里的
`user`/`pass`（容器内 `cat /app/data/traffic/_auth` 可读）。

## 能力边界

镜像**未预置内网隧道工具**（chisel / suo5）。`packaging/tools-manifest.json` 里
这两个条目只有 linux/amd64 二进制，镜像未打包。因此：

- **开箱可用**：外网自动化探索——资产图、探索图、planner/worker 编排、RoE 权限、
  蜜罐识别、MITM 流量证据链、漏洞验证闭环
- **开箱不可用**：立足点（webshell）、多层代理隧道、内网拓扑、凭据库——
  这些需要你自行把对应平台的二进制投递到 `<工程目录>/data/tools/`

启动日志里的 `[tunnel] chisel 二进制不可读 ... Deploy 将报明确错误` 是已知情况，
不是故障。引擎对此的处理是诚实的：功能不可用时明确报错，不装活。

## 端口

默认 8787（HTTP）/ 8788（流量代理），工具界面可改。启动前用
`ServerSocket.bind` 预检，冲突时**在启动前**就报出具体端口号，而不是让 compose
失败后留下一堆半启动容器。改完端口直接重试，override 会同步更新。

只映射到 `127.0.0.1`，不对外暴露。

## 构建失败诊断

「构建镜像」按钮会识别四类高频失败并给出可操作的提示，而不是把 docker 的原始
输出转述给你：

| 失败特征 | 提示 |
| --- | --- |
| `Cannot connect to the Docker daemon` | Docker 未运行，给跳转按钮 |
| `403 Forbidden` + mirror 域名 | 镜像加速器失效，引导检查 Docker Engine 的 `registry-mirrors` |
| `Client.Timeout` / `request canceled` | 网络不通，检查 VPN/代理 |
| `POSTGRES_PASSWORD` 未设置 | 缺少 `.env`，给生成默认值入口 |
| `playwright install` / `azureedge` | chromium 下载失败，提示检查 VPN 且已完成的层有缓存 |

未命中任何模式时回退展示原始输出尾部，保留可诊断性。

## 应用退出时

默认「退出即停」：应用退出时执行 `docker compose stop`。可在界面关闭，关闭后
容器在后台继续运行。

无论开关状态如何，**只 `stop`，绝不 `down -v`**——不删数据卷，不碰工程目录文件。

## 许可边界

上游 ARTEX（`Autumn-27/ARTEX` 及二开分支 `r0th-m/artex-ymh`）采用 **AGPL-3.0**。
本项目为 MIT。

当前集成方式不构成衍生作品：

- 无代码链接、无源码复制、无静态/动态库依赖
- 通信全部是进程间 HTTP（子进程 + 浏览器打开）
- 引擎连同其前端、数据库完整运行在容器内

**会突破边界的是**：把 artex 的 Go 源码复制进本仓库编译、或在 Dart 侧内嵌其代码。
未来若要在 Flutter 里实现引擎 API 客户端，那仍然是进程间通信，不构成衍生；
但任何形式的源码合入都需要重新评估许可影响。

上游另有一条使用限制声明：仅限本地隔离环境与授权明确的实验，不得用于对任何
线上系统发起扫描或攻击。本工具继承这一约束。
