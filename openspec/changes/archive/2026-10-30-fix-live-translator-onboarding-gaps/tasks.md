## 1. 工具分类修正

- [x] 1.1 `registry.dart` 的 `LiveTranslatorToolDefinition.category` 从 `ToolCategory.ai` 改为 `ToolCategory.note`

## 2. 设备选择 UI（核心漏接修复）

- [x] 2.1 `live_translator_page.dart` initState 调用 `AudioCaptureService.listDevices(ffmpegPath)` 枚举设备，存入 state
- [x] 2.2 识别设置区新增设备下拉框（显示设备名 + 通道数），枚举期间显示"正在枚举设备…"
- [x] 2.3 实现预选优先级：记忆索引（名字校验）> 虚拟声卡关键词（Soundflower|BlackHole|虚拟|aggregate|聚集）> 第一个
- [x] 2.4 从 `SettingsStore.readToolConfig('live-meeting-translator')` 读 `selectedDeviceIndex`/`deviceName`，应用到 `_coord` 的 `CaptureConfig.deviceIndex`
- [x] 2.5 用户改选设备时写回 `SettingsStore.writeToolConfig`，并更新 `_coord.setConfig`
- [x] 2.6 新增"刷新设备"按钮重新枚举，保持当前有效选择
- [x] 2.7 无虚拟声卡时显示引导文案（说明内录需虚拟声卡如 BlackHole/Soundflower）
- [x] 2.8 `deviceIndex < 0` 时禁用"开始识别"按钮并提示先选设备

## 3. 悬浮窗隐藏/关闭按钮

- [x] 3.1 `live_caption_window.dart` 删除第 112 行包裹 body 的 GestureDetector 死代码（无手势回调）
- [x] 3.2 拖动条新增"隐藏"按钮（`Icons.visibility_off`）与"关闭"按钮（`Icons.close`）
- [x] 3.3 `live_caption_bridge.dart` 主进程 `_handleCaptionCommand` 新增 `hide` / `close` 分支
- [x] 3.4 `live_translator_host.dart` 区分 `hideCaptionWindow()`（hide，识别继续）与 close 流程（先 `coordinator.stop()` 再 `WindowController.close()`，清空 `_captionWindow`/`_captionWindowId`）

## 4. 测试与验证

- [x] 4.1 测试预选优先级逻辑（记忆命中 / 关键词命中 / 回退第一个）
- [x] 4.2 测试 `flutter analyze` 0 error
- [ ] 4.3 手动验证：打开工具见设备列表 → 自动预选 Soundflower → 开始识别不再报错；悬浮窗隐藏识别继续、关闭识别停止；工具出现在"笔记与学习"分类
