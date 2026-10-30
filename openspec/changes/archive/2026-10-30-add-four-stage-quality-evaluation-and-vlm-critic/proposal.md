## Why

在 AIGC 影视制片流水线中，「小说 → 剧本 → 分镜脚本 → 生图提示词与关键帧 → 生视频提示词与视频」是一个四级编译过程，上游的抽象心理描写、时空跳跃、单镜多动作过载或高低落差强行同框，会在下游扩散模型中被指数级放大，导致人物克隆、悬空站立、坐骑消失与画面鬼畜。我们需要建立覆盖全部四个阶段的质量评价标准、自动化自愈改写以及基于多模态视觉大模型（VLM）的关键帧实拍场记验收闭环，将所有缺陷拦截并消灭在耗资高昂的视频生成之前。

## What Changes

- **第一阶段：剧本工坊可拍性审计与外化自愈 (`ScreenplayQualityEvaluator`)**
  - 新增剧本「不可拍心理/修辞/跨度词雷达」（Show-Don't-Tell Linter），自动扫描场次动作描写中的抽象心理词、文学比喻词与时间跨度概括词。
  - 新增场次时空纯度审计（Scene Unity Check）与对白呼吸节奏校验（Speakability Check）。
  - 在「剧本工坊」工具栏与场次卡片提供「可拍性评分」与「一键视听外化（Show, Don't Tell）」自愈改写能力，将抽象心理与修辞转化为可拍摄的微表情、肢体动作与物理反馈。
- **第二阶段：分镜脚本视听语法审计与一键裂变自愈 (扩展 `DirectorValidationEngine` C14~C16)**
  - 新增 **C14（邻镜景别与机位雷同检测）**：遵循 30° 机位法则与景别跨级原则，同场戏连续 $\ge 3$ 镜景别与机位完全雷同时告警并支持一键错落优化。
  - 新增 **C15（单镜动作载荷过载检测）**：量化单镜（3~6s）内的独立动作动词与转折相位，超载时告警并提供一键拆分为连贯双镜。
  - 新增 **C16（高低落差同框一键正反打裂变）**：针对存量或新生成的垂直高低位同框冲突镜头（如三楼窗口 vs 街面），提供「一键裂变为正反打双镜（#A 俯拍 + #B 仰拍）」自愈动作，自动维护 180° 轴线与镜号重排。
- **第三阶段：生图提示词信噪比评分与 VLM 关键帧实拍场记验收 (`KeyframeVisualCritic`)**
  - 在 `StudioShot` 扩展 `vlmCriticResult`（状态、评分、人数/高差/坐骑/景别四项核验结论及修正建议）。
  - 实现 `KeyframeVisualCritic` 服务：调用多模态大模型（VLM）对已生成的关键帧图片（`shot_N.png`）执行实拍场记验收，自动核验：（1）人数与防克隆双胞胎；（2）空间高差与透视合理性（防悬空平地并立）；（3）坐骑与核心道具存续；（4）景别构图匹配度。
  - 在分镜卡片与「连环画预审（Previs）」面板提供「VLM 审图验收」与「全片关键帧一键审图」，不合格镜头醒目标红并支持一键带修正建议重抽关键帧。
- **第四阶段：生视频提示词动势门禁与四维质量健康度仪表盘 (`QualityScorecard`)**
  - 新增 **C17（首帧姿态与视频起始动势衔接校验 & 运镜微动作互斥清洗）**：拦截首帧状态与视频 `0.0s` 动作冲突，清洗剧烈运镜与精细口型互斥。
  - 构建「四维质量健康度评分看板」（剧本可拍度、分镜语法度、生图与关键帧验收度、视频动势安全度），在分镜看板与连环画预审顶部直观呈现百分制健康度，并支持在审计弹窗内一键执行全链路自愈修复。

## Capabilities

### New Capabilities

### Modified Capabilities
- `ai-video-studio/script-workshop`: 增加剧本可拍性四维评价（心理/修辞词外化率、场次时空纯度、对白呼吸节奏）与一键视听外化改写要求。
- `ai-video-studio/shot-continuity`: 扩充导演可执行性审计规则 C14（邻镜景别雷同）、C15（单镜动作过载）、C16（垂直高低落差同框正反打裂变）、C17（首帧与视频起始动势衔接），以及四维质量健康度评分模型。
- `ai-video-studio/shot-production`: 增加基于多模态大模型（VLM）的关键帧视觉场记验收闭环（`KeyframeVisualCritic`）及在分镜看板/连环画预审中的交互与一键自愈。

## Impact

- `lib/tools/ai_video_studio/models/studio_models.dart`: 扩展 `VlmFrameCriticReport` 数据结构与 `StudioShot.vlmCriticReport` 字段序列化。
- `lib/tools/ai_video_studio/services/screenplay_quality_evaluator.dart`: 新增剧本可拍性扫描、评分与 AI 视听外化改写服务。
- `lib/tools/ai_video_studio/services/director_validation_engine.dart`: 扩充 C14~C17 规则、四维质量健康度计分卡（`StudioQualityScorecard`）及分镜一键裂变工具函数。
- `lib/tools/ai_video_studio/services/keyframe_visual_critic.dart`: 新增 VLM 关键帧实拍场记自动审图服务。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart`: 集成剧本可拍性评分徽章、不可拍词诊断弹窗与「一键视听外化」按钮。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 集成四维质量健康度顶栏看板、C14~C17 一键自愈（含高低位裂变双镜、动作过载拆镜）以及单镜/全片 VLM 关键帧审图验收。
