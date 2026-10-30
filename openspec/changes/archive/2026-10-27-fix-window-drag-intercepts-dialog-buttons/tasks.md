## 1. 移除原生侧全局背景拖拽

- [x] 1.1 在 `macos/Runner/MainFlutterWindow.swift` 删除 `self.isMovableByWindowBackground = true`
- [x] 1.2 在 `macos/Runner/MainFlutterWindow.swift` 的 `FlutterMultiWindowPlugin.setOnWindowCreatedCallback` 回调中删除 `window.isMovableByWindowBackground = true`（AppDelegate.swift 中已不存在此设置，PrivateBrowserWindowController.swift 为纯原生 WKWebView 窗口保留不动）

## 2. 用 DragToMoveArea 替换 ActivityBar 顶部占位

- [x] 2.1 在 `lib/shell/activity_bar.dart` 中：
  - 新增 `import 'package:window_manager/window_manager.dart';`
  - 将顶部 `const SizedBox(height: 38)` 替换为 `DragToMoveArea(child: const SizedBox(height: 38, width: double.infinity))`

## 3. 回滚上次错误修复引入的多余 insetPadding

- [x] 3.1 在 `lib/tools/ai_video_studio/ui/storyboard_board.dart` 将 `_MediaPreviewDialog` 的 `insetPadding: const EdgeInsets.fromLTRB(40, 52, 40, 24)` 恢复为 `insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24)`

## 4. 验证与部署

- [x] 4.1 运行 `flutter analyze` 确认无静态错误
- [x] 4.2 运行 `./scripts/deploy_local.sh` 构建并替换本机应用，实机验证弹窗按钮点击恢复正常
