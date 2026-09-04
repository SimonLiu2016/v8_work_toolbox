## Why

当前工具箱存在视觉与交互层面的明显短板：
1. 缺少专属品牌辨识度 Logo，使用默认蓝底白勾；
2. macOS 原生灰色标题栏依然存在，割裂了深色主界面的沉浸感；
3. 纯黑（#141416）底色层次模糊暗沉；
4. 顶部菜单栏状态图标无法正常稳定呈现；
5. 左侧工具列表采用扁平展示，重复且无法支撑后续 20+ 工具的扩展增长；
6. 缺乏统一的 AI 基础设施服务配置能力，后续新增智能化工具时无法复用配置与协议。

因此，需要推行一次系统性的设计升级与架构扩展，重塑工作区导航、设计系统、菜单栏托盘，并建立系统级 AI 与 MCP 客户端配置中心。

## What Changes

- **沉浸式无标题栏窗口**：在 macOS 原生层配置透明标题栏与全尺寸内容视图，让交通灯无缝悬浮于侧边栏上方，彻底消除浅灰色标题条。
- **VS Code 风格活动栏三栏导航**：
  - 左侧活动栏（Activity Bar，~56px）：常驻分类图标（搜索/全部、文件处理、包与构建、系统配置、AI 配置、偏好设置）。
  - 中间分类面板（Panel，~220px）：展示当前分类下的工具卡片/列表，支持搜索过滤、快捷收折为纯图标模式，解决纵向滚动过长与项重复问题。
  - 右侧主工作区：自适应宽度的工具操作界面。
- **中性深灰色阶系统**：采用专业开发工具级别的中性深灰层次（Activity Bar #333333、Panel #252526、Content #1E1E1E、Card #2D2D30），消除死黑与压抑感。
- **全新 V8 品牌 Logo 与托盘图标**：设计深色磨砂微质感 V8 品牌图标，并生成标准尺寸的 macOS 状态栏 Template 图像，修复顶部菜单栏图标不显示问题。
- **系统级 AI 配置能力中心**：
  - 凭证安全存储：采用 macOS Keychain 存储敏感 API Key，避免本地明文泄漏。
  - 多协议供应商：支持 OpenAI 兼容协议（涵盖 OpenAI、DeepSeek、Ollama 等）、Anthropic 协议以及 Google Gemini 协议。
  - 模型发现与槽位映射：支持手动配置与一键接口探测自动发现模型，提供全局能力槽位（文本、多模态、TTS、STT）。
  - 外部 MCP 服务配置：支持配置已运行的第三方 MCP 客户端连接信息（如 stdio / SSE），向所有业务工具统一暴露 `AiService` 调用能力。

## Capabilities

### New Capabilities
- `workspace-navigation`: 三栏式工作区导航架构（Activity Bar + 可折叠分类工具面板 + 交通灯沉浸式融合），修复菜单栏常驻托盘图标与快捷切换。
- `ai-configuration`: 平台级 AI 统一配置中心（macOS Keychain 安全存储、多协议供应商接入、模型自动发现、槽位映射与外部 MCP 客户端连接）。
- `theme-and-brand`: 中性深灰色彩系统与全新 V8 品牌 Logo / 菜单栏高清图标规范。

### Modified Capabilities

## Impact

- `macos/Runner/MainFlutterWindow.swift`: 配置透明标题栏、隐藏标题文字、内容全屏扩展。
- `macos/Runner/AppDelegate.swift`: 重构 `NSStatusItem` 初始化、图像规范与菜单栏交互。
- `lib/theme/app_theme.dart`: 全量更新为中性深灰设计令牌，更新输入框、卡片、背景与文字灰阶。
- `lib/shell/app_shell.dart`: 重构成 Activity Bar + 可折叠 Tool Panel + Content 三栏布局。
- `lib/services/`: 新增 `AiConfigStore`、`AiService`、`KeychainService` 等服务组件。
- 依赖项：引入 `flutter_secure_storage`（用于 macOS Keychain 安全密钥管理）及相关 http 请求依赖。
