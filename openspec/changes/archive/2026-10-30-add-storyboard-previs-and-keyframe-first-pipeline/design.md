## Context

参见 `proposal.md`。当前 `StudioShot` 数据模型与 `StoryboardBoard` UI 深度将 `framePath`（图片）与 `clipPath`（视频）绑定在同一个缩略图中，且一旦 `clipPath` 存在就默认以视频播放器接管交互。
在提示词与多图参考绑定层面，`ImageGenTask` 与 `VideoGenTask` 无差别将出场角色的所有参考图全部作为主要/次要主体注入，触发了扩散模型因人脸权重冲突而导致的人物浮空与多重分身问题。

## Goals / Non-Goals

**Goals:**
- **解耦状态机**：在 `StudioShot` 中引入 `clipStatus`（`none`, `valid`, `stale`）与时间戳缓存击穿，使关键帧与视频生命周期独立，重新生成关键帧后卡片与弹窗优先展示最新图片；
- **故事板连环画预演流 (Comic Previs)**：提供全片关键帧一键批量生成与横向连环画画卷视图，让创作者以极低成本（几分钱/张）提前排查静态构图冲突；
- **关键帧 1 选 4 抽卡**：为单镜头提供 4 张微变体首帧候选图并行生成与交互式挑选；
- **工业级规约与参考图动态收窄**：过肩与远景镜头动态收窄 `faces` 角色参考图（只下发画面正面主体，远景配角仅保留文本描述），剥离首帧五官词，远景禁用 Lip-Sync 口型，高低落差自动建议正反打。

**Non-Goals:**
- 不替换底层扩散模型供应商协议（继续兼容 Agnes 2.5 Flash / Wan / Minimax 等）；
- 不自动从磁盘硬删除旧视频文件（标记为 `stale` 保留，防止用户误操作丢失）。

## Decisions

### 1. `StudioShot` 模型演进与状态机
在 `StudioShot` 增加以下轻量字段：
- `clipStatus`: `none` | `valid` | `stale`（默认为 `none`，视频生成成功后为 `valid`；当该分镜触发新的生图并成功持久化后，自动翻转为 `stale`）；
- `candidateFramePaths`: `List<String>`（存储最近一次 1 选 4 抽卡生成的临时候选图相对路径）；
- `activeFaceCharacterIds`: `List<String>?`（若非空，则强制指定仅向生成 API 提交该列表内角色的人脸参考图，其余角色降级为背景文本）。

### 2. Flutter 内存图片缓存彻底击穿 (Cache-Busting)
在 `_Thumbnail` 和 `_MediaPreviewDialog` 中，将：
```dart
Image.file(_frameFile!)
```
改造为：
```dart
Image.file(
  _frameFile!,
  key: ValueKey('${_frameFile!.path}_${_frameFile!.existsSync() ? _frameFile!.lastModifiedSync().millisecondsSinceEpoch : 0}'),
  fit: BoxFit.contain,
)
```
利用文件最后修改时间戳作为 Flutter Widget Key，当底层文件被重写时强制废弃旧 RenderObject 与底层 ImageStream，毫秒级呈现最新关键帧。

### 3. 参考图动态收窄 (Reference Scoping) 算法
在 `PromptAssembler` 与 `ImageGenTask` 中：
- 分析分镜的 `cameraMove`、`prompt`、`dialogue` 与空间布局：
  - 若为“过肩俯拍 (OTS)”、“三楼向街道俯视”等高落差场景，主说话者在近景窗台，地面人物为远景；
  - 自动将 `characters` 中处于远景或背对镜头的角色移出 `adapter` 参考图数组，仅保留近景主体 1 张人物图；
  - 在 Prompt 中将远景角色转化为纯环境描述：`a young man on a donkey in the distant street below (background element, no face reference)`。

### 4. 连环画预审卷轴 (Comic Storyboard Review) 视图设计
在分镜看板工具栏增加切换按钮：`[ 标准看板 | 连环画预审 ]`。
- 进入“连环画预审”后，展示可横向顺滑滚动的画卷，卡片按大图比例（16:9 / 9:16）并列呈现；
- 底部显示台词与景别，卡片悬浮提供“重抽 1 张”与“1 选 4 抽卡”快捷操作；
- 顶部提供“一键生成全片关键帧”按钮，直观显示进度条。

## Risks / Trade-offs

- **[Risk]** 1 选 4 抽卡并发消耗更多的生图并发槽位 $\rightarrow$ **Mitigation**: 抽卡仅限用户手动针对单镜触发，不参与全片批量运行；抽卡请求使用独立子标识并在选定后清理未选中候选缓存。
- **[Risk]** `lastModifiedSync()` 在高频重绘时的性能 $\rightarrow$ **Mitigation**: 仅在 Widget `build` 时获取一次，macOS 本地 APFS SSD 耗时通常小于 0.05ms，无卡顿风险。
