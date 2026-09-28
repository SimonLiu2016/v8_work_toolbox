## Context

项目已有 `ProxySettings`（单例，持久化 host/port/enabled）和 `AppHttpClient`（统一 HTTP 出口，读取 `ProxySettings.findProxyFor`）。现有代理配置是手动填写 host:port，放在 `ai_config_page.dart` 的一个 Tab 中。本变更的核心是将「手动填写」替换为「订阅驱动 + mihomo 进程管理」，并将代理管理提升为独立系统页。

## Goals / Non-Goals

**Goals:**
- 内嵌 mihomo 二进制，应用完全自包含，不依赖外部代理软件
- `NetworkProxyService` 作为新单例管理 mihomo 进程和节点配置，最终输出写入已有 `ProxySettings`
- 各工具通过 `PerToolProxySetting` 独立决定是否走代理，`AppHttpClient` 不变
- 代理严格限于进程内 HTTP 请求，不修改 macOS 系统代理设置

**Non-Goals:**
- TUN 模式或系统全局代理（需 root 权限、系统扩展）
- 多订阅地址管理（当前只需一个订阅 URL）
- mihomo 版本自动更新（直接打包固定版本）
- SOCKS5 出口（仅暴露 HTTP 7890，已足够 AppHttpClient 使用）

## Decisions

### 决策 1：内嵌 mihomo 而非 sing-box

**选择**：mihomo（原 clash-meta）。  
**理由**：mihomo 的配置格式与 Clash 订阅 YAML 完全兼容，订阅中的节点配置可直接写入 mihomo config，无需格式转换；sing-box 使用不同的 JSON 配置格式，需额外转换层。mihomo 暴露 REST API（`:9090`）可直接用于测速，无需额外实现。  
**替代方案**：sing-box —— 功能更强但配置格式与 Clash 订阅不兼容，转换复杂度高。

### 决策 2：mihomo 直接打包进 app bundle

**选择**：`macos/Runner/Resources/mihomo`（arm64 单架构二进制，~15MB）。  
**理由**：应用仅供个人使用，用户设备确定为 arm64 Mac，打包单架构足够；无需动态下载，离线也能使用；打包方式与现有 `Resources/` 内其他资源一致。  
**替代方案**：运行时动态下载 —— 首次使用需网络且增加版本管理复杂度，不适合此场景。

### 决策 3：NetworkProxyService 输出到已有 ProxySettings

**选择**：`NetworkProxyService` 选中节点并启动 mihomo 后，调用 `ProxySettings.instance.save(host: '127.0.0.1', port: 7890, enabled: true)`，与现有 `AppHttpClient` 和 MCP 注入路径完全兼容，无需改动。  
**理由**：`ProxySettings` 已是全局单例，所有工具已通过 `AppHttpClient.create()` 读取，此路径零风险。  
**替代方案**：直接在 `AppHttpClient` 中引用 `NetworkProxyService` —— 增加耦合，`ProxySettings` 作为中间层更干净。

### 决策 4：工具级代理开关存储在 ProxySettings 内

**选择**：`ProxySettings` 增加 `Map<String, bool> perToolEnabled`，key 为工具 id（`'ai-assistant'`、`'doc-audio-reader'`），持久化到同一 `proxy.json`。工具初始化时读取，默认值为 `false`（默认不启用代理）。  
**理由**：集中存储，单一持久化路径；工具开关变更通过 `ProxySettings.notifyListeners()` 通知所有监听者。

### 决策 5：mihomo config 生成策略

**选择**：每次选中节点时，生成包含单节点的最小化 config.yaml，写入 `AppPaths.configDir/mihomo_config.yaml`，然后以该文件启动（或重启）mihomo 进程。  
**mihomo config 结构**：
```yaml
port: 7890          # HTTP 代理端口
socks-port: 7891    # SOCKS5（备用，暂不使用）
allow-lan: false    # 严禁外部访问，仅本机
log-level: silent   # 不写日志文件
external-controller: 127.0.0.1:9090  # REST API，用于测速
proxies:
  - {<选中节点的完整字段>}
proxy-groups:
  - name: PROXY
    type: select
    proxies: [<节点名称>]
rules:
  - MATCH,PROXY
```

### 决策 6：测速通过 mihomo REST API

**选择**：测速时向 `http://127.0.0.1:9090/proxies/<name>/delay?url=http://www.gstatic.com/generate_204&timeout=5000` 发 GET 请求，解析返回的 `delay` 字段（毫秒数）。  
**理由**：mihomo 已内置延迟测试逻辑，无需在 Dart 侧自行建立 TCP 连接或发 HTTP 请求穿透代理。  
**注意**：测速时 mihomo 必须已启动（持有 config 中所有节点），因此测速场景下 mihomo config 需包含全部节点（而非单节点），仅 proxy-groups 的 selected 指向当前选中节点。

### 决策 7：全量节点 config vs 单节点 config

**选择**：启动 mihomo 时始终使用**全量节点 config**（`proxies:` 包含订阅中的所有节点），`proxy-groups` 的 selected 指向当前选中节点。切换节点时通过 mihomo REST API `PUT /proxies/PROXY {"name": "<节点名>"}` 动态切换，无需重启进程。  
**理由**：避免每次切换节点都重启 mihomo（重启有约 0.5-1s 延迟），REST API 切换即时生效；全量 config 也使测速可对所有节点进行。  
**替代方案（被否决的决策 5）**：单节点 config + 重启 —— 切换慢，测速需要特殊处理。

## Risks / Trade-offs

- **mihomo 二进制权限问题** → 首次运行前需 `chmod +x`，在 `MihomoProcessManager.start()` 中检查并设置。
- **macOS Gatekeeper 阻止未签名二进制** → 项目已通过取消沙箱（fix-argocd-service-list-and-unsandbox-app）解决 entitlements，但 Gatekeeper 仍可能拦截，需在构建脚本中对 mihomo 执行 `xattr -d com.apple.quarantine` 或通过 Xcode 的 Copy Files Build Phase 处理。
- **订阅下载走直连还是代理？** → 首次拉取订阅时 mihomo 尚未启动，无代理可用，订阅下载必须走直连。这是合理的：用户配置订阅是代理启动的前提，不存在鸡蛋问题。
- **节点数量大时全量 config 体积** → 典型订阅节点数为 50-200，YAML 体积约 50-200KB，mihomo 解析极快，无性能问题。
- **mihomo 进程端口冲突** → 若用户同时运行 Clash Verge，7890 可能被占用，需在启动前检测端口可用性，可备选 17890。

## Migration Plan

1. 删除 `ai_config_page.dart` 中的代理 Tab（`_buildProxyTab` 方法及其引用）
2. `ProxySettings` 现有持久化结构新增 `perToolEnabled` 字段（向后兼容，缺失时默认空 Map）
3. 现有 `AppHttpClient`、MCP 注入路径无需修改
4. 现有手动配置的代理设置在迁移后失效（用户需在新页面重新通过订阅选节点）；因是个人工具，无需迁移向导
