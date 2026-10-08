## Context

当前 Web 资产侦察模块（`WebReconView`）采用三阶段工作流：
1. `SubfinderService.run`：被动子域名枚举
2. `HttpxService.run`：HTTP 存活探测与指纹识别
3. `KatanaService.run`：端点爬虫

在现有实现中，阶段 2 的探测列表仅包含 `subs.map((s) => s.host)`，完全漏掉了用户填写的原始根目标；同时由于未对用户输入进行 URL 清洗与 IP 判别，当用户输入如 `http://192.168.1.1` 时，Subfinder 误从 Wayback 历史归档中拉取拼写错误的垃圾域名，导致假地址直接入库，真目标从未被探测。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 提供目标输入清洗与分类（自动识别 IPv4、IPv6、域名与协议端口）。
- IP/内网目标自动跳过子域名枚举，直接启动 HTTP 存活探测。
- 存活探测列表必须完整保留用户输入的原始目标（Root/Apex Target）。
- 仅将验证存活、具备有效 HTTP 响应的端点写入资产库，过滤历史失效死链。
- 提供 Dart 原生 `HttpClient` 测活兜底，规避外部 CLI `httpx` 环境缺失或被 Python 包冲突导致静默失效的问题。

**Non-Goals:**
- 不改变 Katana 爬虫本身的执行机制。
- 不影响正常公网域名（如 `v8en.com`）执行标准的 subfinder 子域名挖掘。

## Decisions

### 1. 目标智能清洗与类型分流（Target Normalizer）
- **设计决策**：实现 `WebTargetInfo.parse(String raw)`：
  - 剥离前缀（`http://`、`https://`）与尾部路径、参数；
  - 提取 Host（域名或 IP）与可选端口；
  - 利用 `InternetAddress.tryParse` 判定是否为 IP 地址；
  - 判定是否为 `localhost`、私有 IP 或无根域标识。
- **分流机制**：
  - 若目标全为 IP/Localhost：直接跳过阶段 1，并在日志中明确提示 *“目标为 IP/内网地址，自动跳过子域名枚举，直达 HTTP 存活探测”*；
  - 若包含公网域名：仅将域名送入 `subfinder`。

### 2. 根目标全流程保全（Keep Root Targets）
- **设计决策**：构建阶段 2 探测列表时，将**清洗后的用户原始目标**与 **subfinder 发现的子域名**进行 `Set` 合并去重：
  ```dart
  final probeTargets = <String>{
    ...parsedInputs.map((e) => e.targetUrlOrHost),
    ...subs.map((s) => s.host),
  }.toList();
  ```
- **效果**：无论 subfinder 是否发现子域名，原始目标（如 `http://192.168.1.1`）均会 100% 被 `httpx` / 测活引擎完整探测。

### 3. 存活优先资产入库（Alive-First Ingestion）
- **设计决策**：
  - 移除阶段 1 对 subfinder 未测活子域名的盲目全量入库；
  - 统一在阶段 2 测活完成后，将成功响应（返回 200/302/403/401/500 等 HTTP 状态码）的端点持久化到 `session_assets`；
  - 彻底杜绝如 `admin.192.168.1.1` 这种无法解析的假死链污染资产列表。

### 4. Dart 原生 HTTP 测活兜底（Native Fallback）
- **设计决策**：在 `HttpxService` 中增加原生兜底检测：
  - 探测前检测本机 `httpx` 是否为真正的 ProjectDiscovery 二进制（检查 `-version` 或是否为 Python 脚本）；
  - 若 CLI 不可用或未能返回结果，立即无缝降级至 Dart 原生 `HttpClient` 并发探测：
    - 允许自签名证书（`badCertificateCallback`）；
    - 发送轻量 GET/HEAD 请求，提取状态码、Server 响应头与 HTML `<title>`；
    - 确保在零第三方依赖下，`http://192.168.1.1` 等内网 Web 页面能稳定捕获状态码与标题。

## Risks / Trade-offs

- **[风险] 某些特殊内网管理页面仅支持特定端口或只监听 HTTPS**
  - **缓解措施**：原生测活和 httpx 均自动尝试 `http://` 与 `https://`，并尊重用户在输入中显式指定的端口（如 `http://192.168.1.1:8080`）。
