## 1. 原生窗口与菜单栏托盘修复

- [x] 1.1 在 `macos/Runner/MainFlutterWindow.swift` 中配置透明标题栏、隐藏原生标题文字、启用 `.fullSizeContentView`，使内容延伸至窗口顶部
- [x] 1.2 在 `macos/Runner/AppDelegate.swift` 中重构 `setupStatusItem()`，设置明确的 18x18 尺寸、模板图像与层级，修复状态栏图标不显示问题，并保证点击切换窗口正常

## 2. 设计系统与品牌资产

- [x] 2.1 重构 `lib/theme/app_theme.dart`：落地中性深灰色阶系统（Activity Bar `#333333`、Panel `#252526`、Content `#1E1E1E`、Card `#2D2D30`、Border `#3C3C3C`/`#505054`、Text `#D4D4D4`/`#A0A0A0`）
- [x] 2.2 设计并生成全新 V8 品牌桌面应用图标集合，更新至 `macos/Runner/Assets.xcassets/AppIcon.appiconset`
- [x] 2.3 生成高清晰度菜单栏 V8 模板图标资源并接入原生状态栏

## 3. 三栏工作区导航架构

- [x] 3.1 实现 `ActivityBar` 组件（~56px）：顶部预留交通灯安全拖拽边距，提供大类切换（全部工具、文件处理、包与构建、系统与配置、AI配置、偏好设置）
- [x] 3.2 实现 `ToolPanel` 组件（~220px）：展示当前分类工具、分类内搜索过滤、双击或按钮折叠至纯图标模式（~50px）
- [x] 3.3 重构 `lib/shell/app_shell.dart`：组装 Activity Bar + 可折叠 Tool Panel + Content 工作区，对接工具注册表与键盘快捷导航

## 4. 系统级 AI 能力中心与 Keychain 凭证存储

- [x] 4.1 在 `pubspec.yaml` 中引入 `flutter_secure_storage`，封装 `KeychainService`，实现基于 macOS Keychain 的安全 API Key 读写
- [x] 4.2 实现 `AiConfigStore`：管理 `ai_config.json`（供应商列表、协议类型、端点、模型槽位映射与外部第三方 MCP 客户端配置），密钥与 Keychain 关联
- [x] 4.3 实现 `AiService`：封装统一调用入口，支持 OpenAI 兼容、Anthropic 与 Gemini 协议，并实现一键 `/v1/models` 自动探测发现模型
- [x] 4.4 构建 `AiConfigPage` 界面：包含供应商管理（添加/测试/自动探测）、全局模型槽位映射（文本/多模态/TTS/STT）、外部第三方 MCP 服务连接配置

## 5. 验证与收尾

- [x] 5.1 编写 `test/ai_config_test.dart`：验证 AI 存储持久化、Keychain 隔离模拟与模型槽位路由逻辑
- [x] 5.2 运行 `flutter analyze --no-fatal-infos` 达到 0 错误 0 告警
- [x] 5.3 运行 `flutter build macos` 成功编译生成新版本应用
- [x] 5.4 验证窗口沉浸式无边框视觉、菜单栏托盘图标常驻效果与 AI 配置管理全流程
