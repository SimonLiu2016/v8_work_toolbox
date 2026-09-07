## 1. 视觉资产生成与 AppIcon 替换 (Visual Assets Generation)

- [x] 1.1 提取款式 3 高清源图并用 Python 脚本生成全套规范尺寸（16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024）
- [x] 1.2 替换 `macos/Runner/Assets.xcassets/AppIcon.appiconset/` 中所有 PNG 图像并校验 Contents.json
- [x] 1.3 提取精炼六边形矢量轮廓，生成 18x18@1x 与 36x36@2x 纯黑 Template 托盘图标并建立 `TrayIcon.imageset`
- [x] 1.4 精确裁切去除四周多余黑背景底色，施加 macOS 标准 Squircle 透明大圆角蒙版并放大居中，消除程序坞黑边

## 2. macOS 原生系统托盘状态项重构 (Native Tray Item Refactoring)

- [x] 2.1 修改 `macos/Runner/AppDelegate.swift` 中的 `setupStatusItem()`，使用 `NSStatusItem.squareLength` 固定方形尺寸
- [x] 2.2 优先加载 `TrayIcon` Template 资产并设置 `isTemplate = true`，移除易被折叠的文字标题
- [x] 2.3 保留左键唤起/隐藏主窗口与右键快捷菜单的交互逻辑，增加异常保护

## 3. Flutter 端品牌与 Logo 集成 (Flutter App Branding)

- [x] 3.1 增加 Flutter 内部使用的品牌图标资源并在 ActivityBar 顶部及偏好设置关于弹窗中优雅呈现
- [x] 3.2 运行单元测试与分析检查确保 0 警告 0 错误

## 4. 原生打包构建与系统级安装同步 (Bundle & Installation Synchronization)

- [x] 4.1 全量重构编译 macOS 原生应用包，确保包含最新 Swift 原生托盘代码与 Assets.car 资源
- [x] 4.2 将最新构建的应用同步更新至 `/Applications/V8WorkToolbox.app`
- [x] 4.3 刷新 macOS 系统应用图标缓存并重启 Dock，验证程序坞无黑边与菜单栏托盘稳定常驻
