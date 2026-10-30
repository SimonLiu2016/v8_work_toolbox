## Context

详见 `proposal.md`。

当前 Agnes 试炼场在独立窗口（`desktop_multi_window`，运行独立 Flutter 引擎/进程）中运行，其产物直接保存在本地磁盘：
- 试炼场每轮目录：`~/Library/Application Support/V8WorkToolbox/video_studio/agnes_playground/turns/<turn_id>/output/`
- 资产库目录：`~/Library/Application Support/V8WorkToolbox/video_studio/assets/`

因为试炼场卡片 `_buildResult` 只实现了一条文字标签，用户看不到生成的实际媒体；同时，主窗口中打开的「AI 短视频工坊」在启动后单例 `AssetLibrary.instance` 处于 `_loaded == true` 状态，不会自动比对磁盘 `asset_index.json` 的变化，导致跨窗口操作出现视觉断层。

## Goals / Non-Goals

**Goals:**
- 在试炼场卡片内直接预览图片缩略图，点击可弹出高分辨率大图缩放查看器。
- 为图片与视频卡片提供「用默认应用打开」与「在访达中定位」的原生操作。
- 视频产物呈现可点击的海报播放卡片，支持一键调起外部播放器或弹窗预览。
- 改造 `AssetLibrary`，使其具备磁盘文件更新检测（基于修改时间戳比对）与 `reload()` 接口。
- 在 `AssetLibraryPage` 增加刷新按钮，切入资产库时自动触发轻量同步，使试炼场存入的资产立即对用户可见。

**Non-Goals:**
- 不重构 `desktop_multi_window` 的底层通信机制（通过文件系统时间戳比对即可实现零额外开销的高可靠同步）。
- 不破坏现有分镜生成与资产库的契约与字段定义。

## Decisions

### 1. 试炼场产物卡片渲染方案
- **图片**：
  - 在卡片内内嵌 `Image.file`，最大高度限定为 180px，圆角 `borderRadiusSmall`，保持宽高比自适应居中。
  - 缩略图外层包裹 `InkWell`，点击弹出全屏/大图对话框，内部使用 `InteractiveViewer`（支持 1.0~5.0 倍缩放与平移）。
  - 右上角提供「在访达中显示」与「用系统看图打开」快捷按钮。
- **视频**：
  - 渲染深色磨砂海报容器（高度 140px），带视频图标与播放按钮（`Icons.play_circle_fill`）。
  - 点击海报直接调用 macOS 原生 `Process.run('open', [videoPath])` 或弹窗播放，既省资源又绝对兼容所有系统解码器。
- **操作栏增强**：
  - 在卡片操作栏（原「查看请求」、「存入资产库」旁）增加「在访达中显示」按钮（`Icons.folder_open_outlined`），使排查与导出文件极为方便。

### 2. 资产库多窗口缓存自动同步方案
- **比对机制**：
  - `AssetLibrary` 记录内部状态 `int _lastFileModifiedMs = 0`。
  - 每次调用 `ensureLoaded({bool force = false})` 时，读取 `AppPaths.videoStudioAssetIndexFile` 的最后修改时间戳。
  - 若 `fileModifiedMs > _lastFileModifiedMs` 或 `force == true`，清空内存 `_assets` 并重新解析 JSON，随后更新 `_lastFileModifiedMs`。
  - 暴露公开方法 `Future<void> reload()`，方便 UI 随时强制刷新。
- **UI 触发**：
  - `AssetLibraryPage` 工具栏增加一个紧凑的 `IconButton(icon: Icon(Icons.refresh), tooltip: '刷新资产库')`。
  - 当页面初始化或切换分类/检索时，调用 `reload()` 或 `ensureLoaded()`，使新入库资产立即可见。

### 3. 试炼场入库元数据补全
- `PlaygroundStore.collectToAssetLibrary`:
  - 存入资产库时，显式添加标签 `tags: ['试炼场']`。
  - 这样用户可以在资产库通过搜索 `试炼场` 快速过滤出所有在 Playground 调测过程中存下的精品。

## Risks / Trade-offs

- **[多进程并发读写 asset_index.json]** → `AssetLibrary._persist` 原本已采用「临时文件写 + delete + rename」原子写策略，写操作是原子的，不会破坏文件完整性；读取端只需比对修改时间即可安全重新加载。
- **[大图缩略图内存占用]** → `Image.file` 会缓存在 Flutter 图像缓存中；对话框关闭后会自动释放，并在卡片上限制渲染分辨率，不会造成内存泄漏。
