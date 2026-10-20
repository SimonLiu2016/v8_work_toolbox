## Why

在 Agnes 试炼场生成图片或视频后，用户在界面中只能看到一行纯文本文件名与体积（如 `image.png · 3.1MB`），既无图片缩略图也无视频预览或播放器，且无法点击查看大图或定位本地文件。此外，点击「存入资产库」虽已将文件与索引成功写入磁盘，但因 AI 短视频工坊主窗口与试炼场子窗口属于不同进程，主窗口中的 `AssetLibrary.instance` 仅持有启动时加载的旧内存快照，导致用户在资产库中看不到刚刚存入的资产。

解决这两个问题，才能让试炼场真正具备即梦式的多媒体调用直观体验与工作流闭环。

## What Changes

- **试炼场产物直接预览与多媒体交互**：
  - 图片产物：卡片内直接内嵌图片自适应缩略图（`Image.file`），点击弹出自适应大图查看器（支持滚轮缩放查看）。
  - 视频产物：卡片内展示视频占位/首帧海报与播放图标，点击支持内置播放或调用系统默认播放器（`Process.run('open', ...)`）。
  - 操作栏快捷入口：为产物卡片增设「在访达中显示」与「用系统应用打开」按钮。
- **资产库跨进程/多窗口同步与刷新**：
  - `AssetLibrary` 增加磁盘变动感知（基于索引文件最后修改时间比对或主动重载 `reload()`），当磁盘索引比内存新时自动重新读取。
  - `AssetLibraryPage` 顶部增加手动「刷新」按钮，并在页面聚焦或切换至资产库 tab 时自动触发重载。
  - 试炼场存入资产库时提供更合理的分类（默认标记 `other` 但可快捷归位）并添加 `试炼场` 标签便于检索。

## Capabilities

### Modified Capabilities
- `agnes-playground`: 增加产物内嵌预览、缩略图展示、全屏/弹窗放大、系统默认查看与访达定位能力。
- `studio-asset-library`: 增加跨窗口/跨进程索引变动感知、主动刷新与从外部来源即时可见能力。

## Impact

- 受影响代码：
  - `lib/tools/agnes_playground/ui/playground_page.dart`
  - `lib/tools/ai_video_studio/services/asset_library.dart`
  - `lib/tools/ai_video_studio/ui/asset_library_page.dart`
  - `lib/tools/agnes_playground/services/playground_store.dart`
- 关联测试：
  - `test/tools/agnes_playground/playground_page_test.dart`
  - `test/tools/ai_video_studio/asset_library_test.dart`
