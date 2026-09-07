## 1. 资产提取与高清 AppIcon 生成

- [x] 1.1 从款式 2 源图提取流线折带主体并消除网格底纹
- [x] 1.2 施加 22.4% macOS Squircle 透明遮罩并生成全尺寸 PNG 图标集合（16x16 至 1024x1024）
- [x] 1.3 更新 `macos/Runner/Assets.xcassets/AppIcon.appiconset/` 并校验 Contents.json 结构

## 2. 极简流线托盘图标二值化生成

- [x] 2.1 提取折带外轮廓与内环负空间，生成 18x18@1x 与 36x36@2x 纯黑 Template 矢量剪影
- [x] 2.2 更新 `macos/Runner/Assets.xcassets/TrayIcon.imageset/` 资源与 Contents.json

## 3. Flutter 端品牌资产与界面适配

- [x] 3.1 生成 512x512 高清流线折带 Logo 并覆盖 `assets/images/app_logo.png`
- [x] 3.2 校验 ActivityBar 顶部与设置关于弹窗渲染效果，确保无毛边与背景冲突
- [x] 3.3 运行单元测试与分析检查确保 0 警告 0 错误

## 4. 原生编译构建与系统级安装同步

- [x] 4.1 全量重构编译 macOS 原生应用包（Release 构建）
- [x] 4.2 将最新构建的应用同步更新至 `/Applications/V8WorkToolbox.app`
- [x] 4.3 刷新 macOS 系统图标缓存并重启 Dock，验证程序坞与顶部菜单栏托盘稳定常驻
