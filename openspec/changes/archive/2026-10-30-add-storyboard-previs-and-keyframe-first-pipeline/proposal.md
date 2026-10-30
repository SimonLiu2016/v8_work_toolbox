## Why

当前 AI 视频生成工场以“视频为中心”，存在两大核心缺陷：
1. **生成成本与反馈周期严重倒置**：视频扩散生成耗时久（1~3 分钟）、成本高且排队漫长，而在首帧关键帧（T2I，2~3 秒、几分钱）存在物理构图或人物绑定错误（如人脸被平均、人物浮空、双胞胎分身）时，仍然直接渲染视频导致高额算力和时间浪费；
2. **状态遮蔽与体验断层**：在已有视频的分镜上重新生成关键帧后，看板缩略图与预览弹窗被旧视频完全遮蔽，且 Flutter 图片缓存导致用户无法直观查验最新关键帧；同时缺乏正反打机位控制（A/B/C 三机位）、多人物参考图动态收窄（`faces` 白名单）、远景禁台词口型等工业级先验约束。

引入“以图控频（Previs-First）”故事板预演流水线，将关键帧作为一等公民视觉质检门，融合成熟工业级短剧规约，在极低成本下提前排查 95% 的剧本与分镜冲突，彻底解决人脸穿模、浮空与缓存遮蔽问题。

## What Changes

- **以图控频预演模式 (Storyboard Previs Pipeline)**：
  - 新增“全片连环画预审（Comic Storyboard Review）”视图：支持一键低成本快速生成全片首帧关键帧，创作者如翻阅漫画般走查全片人物服装、光影与站位；
  - 新增“关键帧多候选抽卡（1 选 4）”机制：允许单个分镜生成 4 张微变体首帧预览图，选定一张作为锁定的关键帧；
  - 支持首尾双关键帧（First-Frame + Last-Frame）动势约束模式。
- **关键帧与视频状态解耦 & 缓存治理**：
  - 重新生成关键帧后，旧视频自动标记为 `[待重构/已过期]`，卡片缩略图优先展示最新关键帧大图并标注视频状态角标；
  - 预览弹窗智能定向：存在新关键帧或过期视频时，默认直接打开“关键帧大图”Tab，并支持缩放检查细节；
  - 彻底治理 Flutter 内存图片缓存（Cache-Busting）：基于文件修改时间戳强制重绘，消除残留旧图。
- **工业级规约与参考图收窄门禁 (Pre-flight Validator)**：
  - 引入 `faces` 白名单动态收窄：单镜头仅下发视线主体参考图，过肩（OTS）与远景配角严禁下发人脸参考图，彻底杜绝“凭空多出一个人/双胞胎”与“浮空同水平面”；
  - 高低落差/跨场景对话自动拆解为 A/B/C 正反打机位（Master + OTS 双向对拍），保持 180° 轴线一致；
  - 远景（Long Shot）台词口型门禁：远景禁止渲染口型 Lip-Sync，自动降级为画外音或提示转为中景；
  - 首帧 Prompt 净化：自动剥离五官长相文字描述，仅保留服装、构图、光影与实体细节，彻底消除文字与参考图面容的对抗。

## Capabilities

### Modified Capabilities
- `ai-video-studio/shot-production`: 增加关键帧先验（Previs）连环画预审、1 选 4 候选抽卡、关键帧与视频解耦状态管理、Flutter 缩略图缓存击穿与智能弹窗定向。
- `ai-video-studio/shot-continuity`: 增加 `faces` 参考图动态收窄规约（非特写/背影/远景角色禁喂人脸参考图）、A/B/C 正反打高低落差自动拆镜规约、远景禁台词口型规则与首帧长相描述净化门禁。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`（分镜看板 UI、缩略图 `_Thumbnail`、预览弹窗 `_MediaPreviewDialog`、连环画预审卷轴、候选抽卡网格）；
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart` 与 `image_gen_adapter.dart`（首帧长相剔除、`faces` 白名单过滤、参考图动态收窄）；
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` 与 `director_validation_engine.dart`（正反打拆镜建议、远景禁台词口型 Pre-flight 检查、冲突自愈）；
  - `lib/tools/ai_video_studio/models/studio_models.dart`（`StudioShot` 增加 `clipStatus`、`candidateFramePaths`、`activeFaceCharacterIds` 等字段）。
- **APIs & Dependencies**:
  - 依赖现有图像生成适配器（Agnes Image 2.5 Flash / Flux 等），无需新增外部包。
