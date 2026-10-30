## 1. mihomo 二进制准备

- [x] 1.1 从 mihomo GitHub Releases 下载 `mihomo-darwin-arm64` 最新稳定版（v1.18.x），放置到 `macos/Runner/Resources/mihomo`
- [x] 1.2 在 Xcode 项目的 `Runner` Target → Build Phases → Copy Files 中添加 mihomo，确保 Destination 为 `Resources`，勾选 Code Sign On Copy（或 strip bitcode）
- [x] 1.3 添加 Xcode Run Script Build Phase（在 Copy Files 之后）：`xattr -d com.apple.quarantine "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/mihomo" 2>/dev/null || true`，消除 Gatekeeper 隔离属性
- [x] 1.4 验证：构建后运行 `ls -la V8WorkToolbox.app/Contents/Resources/mihomo` 确认文件存在且有执行权限

## 2. ProxySettings 扩展

- [x] 2.1 在 `lib/services/proxy_settings.dart` 的 `ProxySettings` 单例中新增 `Map<String, bool> _perToolEnabled`，`load()` 时从 `proxy.json` 读取 `perToolEnabled` 字段（缺失时默认空 Map），`save()` 时写回（向后兼容现有 JSON 结构）
- [x] 2.2 新增 `bool isToolEnabled(String toolId)` 方法（不存在时返回 `false`）和 `Future<void> setToolEnabled(String toolId, bool enabled)` 方法（持久化并 `notifyListeners()`）
- [x] 2.3 回归验证：现有 `host`/`port`/`enabled` 读写路径不受影响

## 3. ClashSubscriptionParser 实现

- [x] 3.1 新建 `lib/tools/network_proxy/services/clash_subscription_parser.dart`：实现 `ClashSubscriptionParser.parse(String yamlContent)` → `List<Map<String, dynamic>>`，提取 `proxies:` 列表，每个节点保留全部原始字段（不做协议级解析）
- [x] 3.2 处理解析失败情况：YAML 无效或 `proxies:` 为空时抛出具名异常 `ClashParseException(message)`
- [x] 3.3 新建 `lib/tools/network_proxy/services/proxy_node.dart`：定义 `ProxyNode` 数据类，字段 `name`（String）、`type`（String，如 vmess/trojan）、`rawConfig`（Map，保留全部原始字段），支持 `toJson` / `fromJson`

## 4. MihomoProcessManager 实现

- [x] 4.1 新建 `lib/tools/network_proxy/services/mihomo_process_manager.dart`：`MihomoProcessManager` 单例，字段 `Process? _process`、`bool get isRunning`
- [x] 4.2 实现 `Future<void> start(List<ProxyNode> allNodes, String selectedNodeName)` 方法：生成全量节点 `config.yaml`（含 `port: 7890`、`allow-lan: false`、`log-level: silent`、`external-controller: 127.0.0.1:9090`），写入 `AppPaths.configDir/mihomo_config.yaml`，设置执行权限，启动 mihomo 进程，等待 300ms 确认进程存活
- [x] 4.3 实现 `Future<void> switchNode(String nodeName)` 方法：通过 `PUT http://127.0.0.1:9090/proxies/PROXY {"name": nodeName}` 切换节点，无需重启进程
- [x] 4.4 实现 `Future<void> stop()` 方法：向进程发送 SIGTERM，等待退出，超时后 SIGKILL
- [x] 4.5 实现 `Future<int?> testDelay(String nodeName)` 方法：GET `http://127.0.0.1:9090/proxies/<nodeName>/delay?url=http://www.gstatic.com/generate_204&timeout=5000`，返回延迟毫秒数，超时或失败返回 `null`
- [x] 4.6 监听进程退出事件（`process.exitCode`），意外退出时通过 `NetworkProxyService` 通知状态变更为停止

## 5. NetworkProxyService 实现

- [x] 5.1 新建 `lib/tools/network_proxy/services/network_proxy_service.dart`：`NetworkProxyService extends ChangeNotifier` 单例，字段：`String _subscriptionUrl`、`List<ProxyNode> _nodes`、`ProxyNode? _selectedNode`、`bool _isRunning`、`Map<String, int?> _delayResults`
- [x] 5.2 实现 `Future<void> load()` 方法：从 `SettingsStore` 读取 `subscriptionUrl`、`selectedNodeName`、`nodes`（JSON 持久化），若有 `selectedNodeName` 则自动调用 `MihomoProcessManager.start()`
- [x] 5.3 实现 `Future<void> saveSubscriptionUrl(String url)` 方法：校验非空，持久化，`notifyListeners()`
- [x] 5.4 实现 `Future<void> refreshSubscription()` 方法：通过 `AppHttpClient.create()`（直连，代理未启用时）下载订阅内容，调用 `ClashSubscriptionParser.parse()`，更新 `_nodes`，持久化，`notifyListeners()`。失败时抛出携带原因的异常，不清空已有节点列表
- [x] 5.5 实现 `Future<void> selectNode(ProxyNode node)` 方法：若 mihomo 已运行则调用 `switchNode`，否则调用 `start`；更新 `ProxySettings.instance.save(host: '127.0.0.1', port: 7890, enabled: true)` 并持久化选中节点；`notifyListeners()`
- [x] 5.6 实现 `Future<void> testAllDelays()` 方法：并发调用 `MihomoProcessManager.testDelay()` 对全部节点测速，逐步更新 `_delayResults` 并 `notifyListeners()`
- [x] 5.7 实现 `Future<void> setGlobalEnabled(bool enabled)` 方法：更新 `ProxySettings.instance.save(..., enabled: enabled)` 并 `notifyListeners()`
- [x] 5.8 接收来自 `MihomoProcessManager` 的意外退出通知，更新 `_isRunning = false` 并 `notifyListeners()`
- [x] 5.9 在 `lib/main.dart` 的初始化序列中调用 `NetworkProxyService.instance.load()`，在应用退出前调用 `MihomoProcessManager.instance.stop()`

## 6. 网络代理 UI 页面

- [x] 6.1 新建 `lib/tools/network_proxy/ui/network_proxy_page.dart`：顶层 `NetworkProxyPage` StatelessWidget，通过 `ListenableBuilder` / `ChangeNotifierProvider` 监听 `NetworkProxyService`
- [x] 6.2 实现订阅区块：URL 输入框 + 「保存」按钮 + 「刷新订阅」按钮 + 最后更新时间显示；空 URL 提交时显示 SnackBar 错误
- [x] 6.3 实现全局启用开关：`Switch` 绑定 `NetworkProxyService.setGlobalEnabled()`，读取 `ProxySettings.instance.enabled`
- [x] 6.4 实现节点列表：`ListView` 展示所有 `ProxyNode`，每行显示节点名称、协议 chip、延迟数值（或「-」）、单节点测速按钮；点击行触发 `selectNode()`，已选中节点显示勾选高亮
- [x] 6.5 实现「全部测速」按钮：调用 `testAllDelays()`，进行中显示加载状态
- [x] 6.6 实现状态栏：底部固定区域显示 `代理状态: ✅ 运行中 (127.0.0.1:7890)` 或 `⛔ 已停止` 或 `⚠️ 进程异常退出`
- [x] 6.7 节点列表为空时显示空状态提示「尚无节点，请先刷新订阅」

## 7. Activity Bar 与导航集成

- [x] 7.1 在 `lib/shell/activity_bar.dart` 的底部系统图标区域新增「网络代理」图标按钮（`Icons.public_outlined`），位置在「AI 配置」之前或之后（与「AI 配置」并列）
- [x] 7.2 为「网络代理」图标添加绿色指示点：`NetworkProxyService._isRunning && ProxySettings.isConfigured` 时叠加小圆点
- [x] 7.3 在 `lib/shell/app_shell.dart` 中增加 `NetworkProxyPage` 的路由条件，点击「网络代理」时切换内容区到 `NetworkProxyPage`（与 `AiConfigPage` 的处理方式一致）

## 8. 移除旧代理配置 Tab

- [x] 8.1 删除 `lib/shell/ai_config_page.dart` 中的 `_buildProxyTab()` 方法（约 140 行），及 `TabBar` 中对应的 Tab 入口和 `TabBarView` 中的 `_buildProxyTab()` 调用，以及 `_testProxyChannel()` 方法
- [x] 8.2 移除 `ai_config_page.dart` 顶部对 `ProxySettings` 的 import（若无其他用途）
- [x] 8.3 验证：AI 配置页无代理相关 UI 元素，Tab 数量减少符合预期

## 9. 工具代理开关集成

- [x] 9.1 在 `lib/tools/ai_assistant/ui/ai_assistant_page.dart` 的设置/配置区域新增「使用系统代理」`Switch`，读写 `ProxySettings.instance.isToolEnabled('ai-assistant')` / `setToolEnabled('ai-assistant', value)`
- [x] 9.2 修改 `lib/tools/ai_assistant/services/ai_assistant_service.dart` 中创建 HTTP client 的位置：当 `ProxySettings.instance.isToolEnabled('ai-assistant')` 为 `false` 时，使用 `http.Client()`（直连）而非 `AppHttpClient.create()`
- [x] 9.3 在 `lib/tools/reader/ui/doc_audio_reader_page.dart` 的设置区域新增「使用系统代理」`Switch`，读写 `ProxySettings.instance.isToolEnabled('doc-audio-reader')` / `setToolEnabled('doc-audio-reader', value)`
- [x] 9.4 修改 `lib/tools/reader/services/document_parser.dart` 和 `lib/tools/reader/services/tts_engine.dart`：当 `ProxySettings.instance.isToolEnabled('doc-audio-reader')` 为 `false` 时使用直连 `http.Client()`

## 10. 测试与验证

- [x] 10.1 单元测试 `ClashSubscriptionParser`：使用真实订阅 YAML 片段验证节点提取；验证 `proxies:` 为空时抛出 `ClashParseException`
- [x] 10.2 单元测试 `ProxySettings` 新字段：`perToolEnabled` 读写、持久化、默认值行为
- [x] 10.3 手工验证：刷新订阅地址 `https://spacex.airport-ls.top/api/v1/client/subscribe?token=5f83e90a56dc52f33ac384fddbdf626a`，确认节点列表正确展示
- [x] 10.4 手工验证：选中节点 → mihomo 启动 → AI 咨询开启代理 → 发送请求 → 确认走代理（可通过 mihomo 日志或在节点上观察流量）
- [x] 10.5 手工验证：关闭 AI 咨询代理开关 → 再发请求 → 直连（不走 mihomo）
- [x] 10.6 手工验证：应用退出后 `pgrep mihomo` 确认无孤儿进程
- [x] 10.7 全量回归：`flutter test`，确认现有测试无回归
