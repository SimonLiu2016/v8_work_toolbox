## 1. 资产库多进程与多窗口同步

- [x] 1.1 `lib/tools/ai_video_studio/services/asset_library.dart`：在 `AssetLibrary` 增加 `_lastFileModifiedMs` 状态，`ensureLoaded` 时检查 `asset_index.json` 修改时间戳，磁盘较新或 `force: true` 时自动重载
- [x] 1.2 `lib/tools/ai_video_studio/services/asset_library.dart`：增加公开展露的 `Future<void> reload()` 方法
- [x] 1.3 `lib/tools/ai_video_studio/ui/asset_library_page.dart`：工具栏增加手动刷新按钮（`Icons.refresh`），并在 `_load()` 与 tab 激活时检查并重新拉取
- [x] 1.4 `lib/tools/agnes_playground/services/playground_store.dart`：`collectToAssetLibrary` 入库时自动附带 `tags: ['试炼场']` 标签

## 2. 试炼场产物卡片渲染与多媒体交互

- [x] 2.1 `lib/tools/agnes_playground/ui/playground_page.dart`：新增大图预览灯箱对话框（基于 `InteractiveViewer` 支持拖拽缩放、原图查看与快捷操作）
- [x] 2.2 `lib/tools/agnes_playground/ui/playground_page.dart`：改造 `_buildResult`，图片产物渲染内嵌自适应缩略图卡片，并绑定点击触发大图对话框
- [x] 2.3 `lib/tools/agnes_playground/ui/playground_page.dart`：改造 `_buildResult`，视频产物渲染视频海报卡片与居中播放按钮，点击调起播放
- [x] 2.4 `lib/tools/agnes_playground/ui/playground_page.dart`：在 `_buildActions` 增加「在访达中显示」与「用系统应用打开」按钮

## 3. 验证与部署

- [x] 3.1 新增/更新 `test/tools/ai_video_studio/asset_library_test.dart`：覆盖磁盘修改时间变动后的自动重载与 `reload()`
- [x] 3.2 更新 `test/tools/agnes_playground/playground_page_test.dart`：断言图片/视频产物卡片呈现缩略图与快捷操作按钮
- [x] 3.3 运行 `flutter analyze` 与相关单元测试，确保全绿
- [x] 3.4 执行 `./scripts/deploy_local.sh` 完成 Release 本地构建、签名验证与应用替换
