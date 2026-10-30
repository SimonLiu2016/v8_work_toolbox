## 1. 结构与生命周期：Shell 导航保活与状态对齐

- [x] 1.1 `lib/tools/ai_video_studio/ui/studio_shell.dart`：重构 `_buildStage` 为 `IndexedStack`（索引对应 `StudioStage.values`），确保切换导航时各子面板（尤其是 `IdeaIncubatorPanel`）不被 dispose，避免局部状态与导入任务引用丢失。
- [x] 1.2 `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：增强任务引用恢复逻辑。在 `initState` 或 `build` 中，若 `_activeImportId` 为空但 `NovelImportTaskService` 中有属于当前剧集的正在执行或最新任务，自动拾取绑定，确保关窗重开或切回时进度条立即可见。

## 2. 制作类型与全矩阵风格锁系统

- [x] 2.1 `lib/tools/ai_video_studio/models/studio_models.dart`：
  - 在 `StudioProductionType` 枚举中新增 `anime3d`（3D国漫/次世代虚拟剧）。
  - 为 `StudioProductionType` 扩展 `defaultPositiveStyle`（正向风格基准词）、`defaultNegativeStyle`（负向互斥抑制词）及 `motionTendency`（动态镜头偏向），覆盖全部 4 个制作类型（`drama` / `anime` / `narration` / `anime3d`）。
- [x] 2.2 `lib/tools/ai_video_studio/services/prompt_assembler.dart`：
  - 在 `PromptParts` 和 `SegmentPromptParts` 中引入制作类型上下文或正负向基准词映射。
  - 在 `buildShotPrompt` 和 `buildSegmentPrompt` 中根据剧集类型注入专属的正向画风渲染词与负向排他词，彻底实现真人不混动漫、3D不混扁平2D的风格隔离。
- [x] 2.3 `lib/tools/ai_video_studio/ui/project_list_page.dart` 及项目管理：
  - 新建剧集弹窗支持选择 `anime3d`。
  - 新建剧集时根据选择的类型，自动将该类型的 `defaultPositiveStyle` 初始化写入剧集的 `styleTokens` 字段。
- [x] 2.4 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：
  - 在小说全案提取与角色 Prompt 翻译时，感知所属剧集的制作类型（真人/2D/3D/解说），输出契合该视觉风格的角色及场景英文描述。

## 3. IP 主库：图片全屏预览与单张删除能力补齐

- [x] 3.1 `lib/tools/ai_video_studio/ui/series_page.dart`：封装通用的图片预览与管理对话框（支持点击缩略图后通过 `InteractiveViewer` 全屏放大缩放查看原始大图，支持单张参考图二次确认删除并同步清理磁盘文件与元数据）。
- [x] 3.2 角色卡参考图与三视图管理：角色编辑面板中的「基准参考图」支持弹窗列表查看所有图片，三视图生成后显式展示在图片管理列表中并打上「三视图」专属标签，支持点击放大查看大图及删除单张图。
- [x] 3.3 道具库大图预览：道具编辑面板及卡片缩略图添加点击手势，支持弹窗查看高清大图，补齐缩略图与单张参考图的交互闭环。

## 4. IP 主库：场景库 AI 生成图能力补齐

- [x] 4.1 `lib/tools/ai_video_studio/ui/series_page.dart`（场景编辑面板）：对齐道具库的 AI 生图逻辑，新增「生成场景图」按钮，调用 `SystemAiImageAdapter` 基于场景描述、Prompt 及剧集风格锁进行生图并存入场景目录，更新 `referenceImages`。
- [x] 4.2 场景参考图入库：场景编辑面板新增「收进资产库」按钮，调用 `AssetLibrary.addAsset`，将生成的场景图以 `AssetCategory.scene` 录入全局/剧集资产库，支持反查调用记录。
- [x] 4.3 场景参考图预览与删除：场景编辑面板的参考图列表接入 3.1 的全屏预览和单张删除功能。

## 5. UI 布局与配置修正：顶栏文案与模型能力适配

- [x] 5.1 `lib/tools/ai_video_studio/ui/studio_shell.dart`：修正顶栏配置指示按钮文案，`_isLocalDemoMode` 下从「本地免费演示模式 (点击配置)」更正为「⚙ 点击配置 AI 引擎」，消除"演示模式"歧义。
- [x] 5.2 `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`：修复配置弹窗底部按钮在小窗口/紧凑模式下溢出屏幕的布局 Bug（采用 `SingleChildScrollView` 或调整弹性布局）。
- [x] 5.3 模型能力描述校准：核对并校准能力显示，确保与实际能力矩阵（Agnes Video 2.5 720P/1080P/1K/2K、首尾帧与多参考图）一致。

## 6. 验证与部署

- [x] 6.1 运行 `flutter analyze` 与 `flutter test`，修复潜在类型与未定义成员错误。
- [x] 6.2 执行 `./scripts/deploy_local.sh` 重新打包 Release 并部署替换本机 `/Applications/V8WorkToolbox.app`。
- [x] 6.3 验证所有问题点：新建项目 4 种类型的提示词风格锁生效、角色三视图查看删除、场景库 AI 生图与大图预览、创意孵化任务切页签保活、配置按钮文案与弹窗布局。
