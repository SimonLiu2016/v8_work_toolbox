## Context

- `lib/main.dart` 启动时通过 `desktop_multi_window` 参数派生不同的桌面子窗口。然而 `MediaKit.ensureInitialized()` 过去被放在了主窗口专有初始化逻辑段中，子窗口直接 `return` 导致未执行底层 libmpv 初始化。
- `storyboard_board.dart` 的 `_MediaPreviewDialog` 使用了 `Dialog` 容器，在内嵌未正确初始化的 `Video` 纹理时会报错或呈现默认底层灰屏，且需要明确的尺寸约束防止破坏桌面端视口。
- 关键帧生成后，`ImageGenTask` 将图片持久化保存为 `shot_{n}.png`。Flutter 的 `ImageCache` 依据路径进行内存缓存，导致即使磁盘内容更新，前端卡片仍然显示旧图，必须重启销毁进程内存缓存后才展示新图。

## Goals / Non-Goals

**Goals:**
- 将 `MediaKit.ensureInitialized()` 提升至全局入口执行，确保任何子窗口模式下 `Player` 和 `VideoController` 均能正常分配外接纹理与视频硬件解码。
- 在关键帧图片成功落盘时，主动驱逐 `FileImage(outputFile).evict()`，并在前端缩略图组件中以动态版本号/更新时间戳作为缓存 Key 或监听触发器，确保生成完成后界面即时呈现最新图片。
- 完善 `_MediaPreviewDialog` 的尺寸与比例约束，在视频播放异常或尚未生成完全时优雅降级并展示可用预览与操作按钮。

**Non-Goals:**
- 不重构 `desktop_multi_window` 进程间通信机制。
- 不替换 media_kit 为其他播放器引擎。

## Decisions

### 决策 1: MediaKit.ensureInitialized 全局最顶层前置初始化
- **方案**: 在 `main()` 的 `WidgetsFlutterBinding.ensureInitialized()` 之后、判断 `isSubWindow` 之前立即执行 `MediaKit.ensureInitialized()`。
- **原因**: MediaKit 是轻量级 C 库绑定注册，耗时极短（<10ms），放在最顶层可保证后续无论是主窗口还是未来任何子窗口（AI 工坊、独立播放器、笔记）都能无缝使用视频与音频硬件加速能力。

### 决策 2: 双重缓存刷新保障（Evict + 时间戳/版本响应）
- **方案**: 
  1. 数据层：在 `ImageGenTask.run` 将 `outputFile` 写入磁盘后，立即执行 `await FileImage(outputFile).evict();`，将旧的位图从 Flutter 内存图片缓存中剔除；
  2. UI 层：在 `_Thumbnail` 中，加载 `Image.file` 时传入带有文件修改时间或 shot 更新状态的 key（例如 `Key('${_frameFile!.path}_${_frameFile!.lastModifiedSync().millisecondsSinceEpoch}')`），或者在 `_reload()` 触发时保证 Flutter 重构新帧，消除缓存穿透问题。
- **原因**: 双保险方案彻底解决 Flutter 在桌面端对本地同名覆盖文件无法自动感知的通病。

### 决策 3: _MediaPreviewDialog 弹窗约束与容错升级
- **方案**:
  1. 给 Dialog 增加自适应居中约束（最大宽度 960，最大高度 720，内层宽高比自适应 16:9 / 9:16），避免溢出铺满；
  2. 当 `_videoController` 报错或初始化尚未完成时，显示关键帧底图与居中播放/重试/使用系统播放器提示，杜绝整屏黑灰屏。

## Risks / Trade-offs

- **[Risk]** 在子窗口初始化 MediaKit 是否会有额外的内存消耗？
  - **Mitigation**: MediaKit 的动态库绑定加载开销极小，仅在创建 `Player()` 实例时才会分配解码缓冲区，子窗口预初始化没有额外副作用。
