## 1. 基础多媒体运行时全局初始化

- [x] 1.1 在 `lib/main.dart` 中将 `MediaKit.ensureInitialized()` 提升至 `main()` 最顶层，覆盖主窗口与所有桌面子窗口
- [x] 1.2 验证在子窗口启动时 MediaKit 正常注册无崩溃

## 2. 关键帧内存缓存驱逐与 UI 即时刷新

- [x] 2.1 在 `studio_generation_tasks.dart` 的 `ImageGenTask` 中落盘图片后执行 `await FileImage(outputFile).evict()` 驱逐旧缓存
- [x] 2.2 在 `storyboard_board.dart` 的 `_Thumbnail` 中为 `Image.file` 注入基于文件修改时间的动态 Key，确保重新生成后界面无缝替换新图

## 3. 视频预览弹窗尺寸约束与容错增强

- [x] 3.1 为 `_MediaPreviewDialog` 增加视口约束，防止灰屏弹窗撑满窗口
- [x] 3.2 优化播放器初始化与解码异常兜底，展示关键帧底图并支持唤起系统播放器
- [x] 3.3 运行单元测试验证相关流程

## 4. 本地部署与验证

- [x] 4.1 执行 `./scripts/deploy_local.sh` 编译 Release 并热替换本机应用
