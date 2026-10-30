## Why

在“Web 资产侦察”模块中，用户输入单个 IP 或完整 URL（如 `http://192.168.1.1`）时，系统存在两大严重缺陷：
1. **根目标遗失**：阶段 2（HTTP 存活探测）的目标列表仅提取了 Subfinder 发现的子域名，彻底丢弃了用户自己填写的原始根目标，导致像路由器后台、单体 Web 站点的真目标从未被探测与记录。
2. **目标类型失真与脏数据污染**：代码未清洗 `http://` 协议头，且盲目将 IP 地址提交给子域名枚举工具（Subfinder）。Subfinder 误将 IP 当作根域名向公网历史档案检索，返回带有拼写错误的死链垃圾数据（如 `admin.192.168.1.1`）；且在阶段 1 结束时未经存活检测直接入库，造成资产库被无效幽灵地址污染。此外，macOS 上 Python 的同名 `httpx` 包常造成路径拦截。

通过引入智能目标分流（区分 IP/URL 与 FQDN 域名）、保全原始根目标、优化存活优先入库策略，并增强 Dart 原生 HTTP 测活兜底，确保无论是输入路由器 IP 还是企业域名，都能准确捕获真实的 Web 资产。

## What Changes

- **目标输入清洗与分类（Smart Target Routing）**：
  - 自动剥离 `http://`、`https://` 前缀及尾部路径，解析出标准 Host 与端口；
  - 判定目标类型：若为 IPv4 / IPv6 / Localhost / 内网 IP，自动跳过 `subfinder` 子域名枚举阶段，直接进入 HTTP 测活与指纹发现；
  - 若为公网域名（FQDN），则运行 `subfinder`，并将**原始根域名自身**与枚举出的子域名合并去重。
- **根目标保全与完整探测**：
  - 无论是否有子域名产出，原始根目标必被纳入 HTTP 存活探测与爬虫探测流程；
  - 正确识别并解析如 `http://192.168.1.1` 的 200/302 状态、网页标题（如路由器管理登录页）、WebServer 与爬虫端点。
- **存活优先入库策略（Alive-First Ingestion）**：
  - 避免阶段 1 直接将未经解析的被动归档子域名盲目入库；
  - 仅将经过 HTTP 探测响应（或明确解析存活）的目标沉淀为 Web 资产，彻底阻断无效脏数据污染。
- **HTTP 探测器容错与原生 Fallback**：
  - 解决系统中 Python 同名 `httpx` 拦截问题；
  - 在 CLI `httpx` 不可用或发生异常时，提供 Dart 原生 `HttpClient` 测活兜底（自动拉取状态码、Title、Server 响应头），确保探测零失败。

## Capabilities

### New Capabilities
- `security/web-recon-accuracy`: 规范 Web 资产侦察中的目标类型识别、输入清洗、根目标保全、子域名存活验证与原生探测容错。

### Modified Capabilities
<!-- None -->

## Impact

- **UI 页面**：
  - `lib/tools/security_toolbox/ui/web_recon_view.dart`
- **后台服务**：
  - `lib/tools/security_toolbox/services/web_recon_services.dart`
  - `lib/tools/security_toolbox/services/security_process_runner.dart`
- **部署发布**：
  - 代码更新后执行 `./scripts/deploy_local.sh` 编译部署。
