## 1. 数据模型与四维计分卡基座 (Data Model & Scorecard Foundation)

- [x] 1.1 在 `studio_models.dart` 中新增 `VlmFrameCriticReport`（包含 `score`, `passed`, `characterCountOk`, `noCloneArtifact`, `spatialElevationOk`, `mountPropOk`, `shotScaleOk`, `issues`, `promptFixSuggestion`, `evaluatedAt`）并扩展 `StudioShot.vlmCriticReport` 字段、JSON 序列化及 `copyWith`
- [x] 1.2 在 `director_validation_engine.dart` 中定义 `StudioQualityScorecard`（包含剧本可拍度、分镜语法度、关键帧与生图信噪比、视频动势安全度及综合评分）

## 2. 第一阶段：剧本可拍性评估与一键视听外化 (`ScreenplayQualityEvaluator`)

- [x] 2.1 创建 `lib/tools/ai_video_studio/services/screenplay_quality_evaluator.dart`，实现不可拍心理词、文学比喻词、时间跨度概括词扫描器，以及场次时空混杂检测与长句对白呼吸过载检测
- [x] 2.2 在 `ScreenplayQualityEvaluator` 中实现 AI「一键视听外化（Show, Don't Tell）」改写能力与确定性规则回退，将抽象心理与修辞转化为可拍的微表情与物理动作并保留原著锁定台词
- [x] 2.3 在 `ScreenplayPanel`（`lib/tools/ai_video_studio/ui/screenplay_panel.dart`）顶栏集成「剧本可拍性评分徽章」、可拍性诊断报告弹窗与「一键视听外化」修复入口

## 3. 第二与第四阶段：分镜语法进阶规则 C14~C17 与一键正反打裂变 (`DirectorValidationEngine`)

- [x] 3.1 在 `DirectorValidationEngine` 中实现 C14（连续三镜景别机位雷同检测）、C15（单镜多动词过载检测）、C16（高低位同框正反打裂变建议）、C17（首帧姿态与视频起始动作衔接及运镜微动作互斥检测）
- [x] 3.2 实现高低位同框镜头「一键裂变为正反打双镜（#A 俯拍 + #B 仰拍）」与过载镜头「一键拆分为双镜」工具函数，支持后续镜号顺延、片段映射更新及磁盘媒体文件倒序重命名对齐
- [x] 3.3 在 `DirectorValidationEngine` 中实现 `computeScorecard` 方法，输出完整的 `StudioQualityScorecard` 四维百分制健康度

## 4. 第三阶段：VLM 关键帧实拍场记自动审图验收 (`KeyframeVisualCritic`)

- [x] 4.1 创建 `lib/tools/ai_video_studio/services/keyframe_visual_critic.dart`，支持读取本地关键帧图片并通过多模态 Vision 接口执行四维场记验收（防克隆、查高差、查坐骑道具、查景别），支持静态回退分析
- [x] 4.2 在 `StoryboardBoard`（含标准分镜卡、连环画预审 `_ComicShotPanel` 及审计报告弹窗）集成四维质量健康度顶栏看板、单镜/全片 VLM 审图按钮、审图告警徽章及「采纳建议重抽 / 一键裂变正反打双镜」自愈闭环

## 5. 单元测试与本机应用部署 (Testing & Local Deployment)

- [x] 5.1 编写单元测试 `test/tools/ai_video_studio/four_stage_quality_and_vlm_critic_test.dart`，覆盖剧本可拍性扫描与外化、C14~C17 规则、高低位分镜裂变双镜、四维计分卡及 VLM 审图报告解析与持久化
- [x] 5.2 执行 `flutter test` 确保全量测试通过，并按工程规范执行 `./scripts/deploy_local.sh` 完成本机 Release 应用构建与热替换
