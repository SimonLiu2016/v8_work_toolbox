## Why

V8WorkToolbox 中的 AI 咨询、文档阅读器 TTS 等功能需要访问境外服务，但目前无任何进程内代理能力，完全依赖系统 TUN 模式兜底。当用户希望精细控制"哪个工具走代理、走哪个节点"时，软件无法满足。我们需要一个完全自包含的代理管理器，不依赖外部软件（如 Clash Verge），从订阅地址获取节点列表、在应用内选节点，且代理作用域严格限于本应用，不影响浏览器或其他软件。

## What Changes

- **新增「网络代理」系统页**：位于 Activity Bar 底部（与「AI 配置」并列），独立于工具网格，负责订阅管理、节点列表展示、速度测试与当前节点选择。
- **捆绑 mihomo 二进制**：直接打包进 `app bundle/Contents/Resources/mihomo`（macOS arm64），作为进程内代理内核，按需启停，监听 `127.0.0.1:7890`（HTTP）/ `127.0.0.1:7891`（SOCKS5）。mihomo 的作用域是本进程发出的 HTTP 请求，不修改任何 macOS 系统代理设置。
- **Clash 订阅解析**：从用户配置的订阅 URL 下载 YAML，解析 `proxies:` 字段，支持全部协议（VMess / VLESS / Shadowsocks / Trojan / Hysteria2 / TUIC 等）。
- **节点速度测试**：通过 mihomo REST API（`/proxies/{name}/delay`）对各节点测延迟。
- **进程内代理集成**：`NetworkProxyService` 管理 mihomo 进程生命周期，选中节点后生成最小化 `config.yaml` 并写入 `ProxySettings.instance`（已有单例），现有 `AppHttpClient` 和 MCP 子进程注入路径无需改动。
- **工具级代理开关**：AI 咨询（`ai_assistant_page.dart`）和文档阅读器（`doc_audio_reader_page.dart`）各新增「使用系统代理」开关；开启后该工具的 HTTP 请求走 mihomo，关闭后直连。
- **移除手动代理配置 Tab**：`ai_config_page.dart` 中现有的手填 host:port 代理 Tab 迁移到「网络代理」页，原 Tab 删除。

## Capabilities

### New Capabilities

- `network-proxy`: 应用内嵌代理管理器——订阅管理、Clash YAML 解析、节点列表与速度测试、mihomo 进程生命周期管理、进程内 HTTP 代理出口（`127.0.0.1:7890`），作用域严格限于本应用，不修改系统代理设置。

### Modified Capabilities

- `ai-configuration`: 移除现有代理手动配置 Tab（host/port），代理配置入口迁移到独立的「网络代理」系统页。
- `doc-audio-reader`: 新增「使用系统代理」开关，TTS 引擎和文档抓取可按需走 `AppHttpClient` 代理通道。
- `workspace-navigation`: Activity Bar 底部新增「网络代理」系统页入口。

## Impact

- **新文件**：
  - `lib/tools/network_proxy/` 目录（`ui/network_proxy_page.dart`、`services/network_proxy_service.dart`、`services/clash_subscription_parser.dart`、`services/mihomo_process_manager.dart`）
  - `macos/Runner/Resources/mihomo`（捆绑二进制，不进 git LFS 跟踪的可执行文件）
- **修改文件**：
  - `lib/shell/activity_bar.dart`：新增「网络代理」图标入口
  - `lib/shell/app_shell.dart`：路由「网络代理」页
  - `lib/shell/ai_config_page.dart`：删除代理 Tab
  - `lib/tools/ai_assistant/ui/ai_assistant_page.dart`：新增代理开关
  - `lib/tools/reader/ui/doc_audio_reader_page.dart`：新增代理开关
  - `lib/services/proxy_settings.dart`：新增 `perToolEnabled` Map，供各工具开关读写
  - `lib/main.dart`：应用启动时初始化 `NetworkProxyService`
- **新依赖**：`yaml: ^3.1.0`（pubspec 中已有或需补充）、`process_run`（已有或用 `dart:io Process`）
- **无系统代理写入**：mihomo 仅监听本地端口，不调用 `scutil`，不写 `SystemConfiguration`
