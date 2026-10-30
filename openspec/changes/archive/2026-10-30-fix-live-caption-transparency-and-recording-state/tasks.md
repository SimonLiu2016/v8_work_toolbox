## 1. 原生样式调用点收敛与真实透明度驱动

- [x] 1.1 在 `lib/tools/live_translator/services/live_translator_host.dart` 的 `openCaptionWindow` 中主进程调用 `ContextServicesBridge.instance.styleLiveCaptionWindow()`
- [x] 1.2 在 `lib/tools/live_translator/ui/live_caption_window.dart` 中移除子进程内失效的 `styleLiveCaptionWindow` 调用
- [x] 1.3 在 `lib/tools/live_translator/ui/live_caption_window.dart` 的 `_cycleOpacity` 和 `_loadConfig` 中联动调用 `windowManager.setOpacity(_opacity)`

## 2. 悬浮窗记录状态响应式呈现

- [x] 2.1 在 `LiveCaptionWindowApp` 中定义 `_isRecording` 状态并在 `_applyState` 中提取 `map['isRecording']`
- [x] 2.2 在 `_buildDragBar` 中将静态记录按钮改造为响应式图标（进行中 `Icons.stop_circle` 红色，未进行 `Icons.fiber_manual_record` 灰白色）与明确 Tooltip

## 3. 验证与本地应用构建部署

- [x] 3.1 运行 `flutter analyze` 确保代码无分析告警与错误
- [x] 3.2 运行 `flutter test test/live_translator_test.dart` 确保单元测试全数通过
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译 Release、重签名并替换本地运行应用
