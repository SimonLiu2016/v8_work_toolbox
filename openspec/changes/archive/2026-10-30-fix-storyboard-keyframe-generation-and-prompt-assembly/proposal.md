## Why

在分镜看板执行“批量生成关键帧”时，存在两个严重破坏核心工作流的问题：
1. **并发生成数据竞争导致图片丢失与闪烁**：多个异步生图/生视频任务并发完成时，各任务基于任务启动时的旧集快照覆盖回写 `episode.json`，后完成的任务直接抹除了先完成任务的 `framePath`，且磁盘自愈逻辑因文件名匹配规则缺失（未匹配 `shot_*.png/mp4`）无法自动找回，表现为分镜图片一会有一会没有、最终丢失。
2. **生图提示词信息污染与冗余堆砌**：
   - 室内/地下场景（如“巡城司大牢”）生成场景卡时盲目混入仙侠室外锚点（云海、奇峰仙山、亭台楼阁），导致场景底图严重违和；
   - 在多图合成模式下，已有角色三视图参考图的情况下，提示词装配器依然机械地在 `【同框人物与站位】` 中塞入长达 500+ 字的 IP 主库容貌与服装静态描述，不仅语义严重错位，而且与参考图注意力打架，导致关键帧的核心动作（`actionZh`）被稀释到不足 2%，无法体现分镜重点且生成图片雷同。

## What Changes

1. **原子化镜头更新机制与自愈补全**：
   - 在 `StudioProjectManager` 中新增 `updateShot(seriesId, episodeId, shotNumber, (shot) => ...)` 原子操作，在写锁链路中先读取磁盘最新 JSON，仅定位更新目标分镜的元数据后落盘，彻底根除并发旧快照覆盖问题。
   - 重构 `ImageGenTask` 与 `VideoGenTask`，任务完成后仅调用 `updateShot` 写入完成状态与媒体文件名。
   - 修复 `StudioProjectManager._healEpisodeMediaIfNeeded`，同时支持探测 `shot_${shot.number}.png` 与 `shot_${shot.number}.mp4`，打开或刷新看板时自动恢复已落盘图片。
2. **室内与地下场景提示词环境净化**：
   - 在 `ScenePromptBuilder.buildPositivePrompt` 中引入封闭/室内场景检测（`isEnclosedScene`），对室内、牢房、密室等封闭场景自动滤除 `era.environmentAnchor` 和 `styleTokens` 中的室外互斥词（云海、奇峰仙山、开阔天空等），并注入室内材质与局部微光。
3. **提示词组装器（PromptAssembler）多图合成精简与同框站位重构**：
   - 当分镜已绑定角色三视图/面部参考图时，从提示词中剥离 `basePromptPositive`（主库常驻样貌与服饰长文），仅保留角色名称、即时形态变体差异（`variation.positiveDelta`）以及即时态势，把注意力权重最大化让渡给核心动作 `actionZh`。
   - 还“同框人物与站位”本色：该字段专职负责人数、画内方位与主客交互构图（结合分镜台账 `screen_position`），不再输出角色外观档案，单人镜头同理净化。
   - 优化多图合成场景保留用语：将生硬的“保留空间布局”调整为“保留场景建筑材质风格与光影氛围，运镜根据分镜动作动态取景”，解除机位定死导致的连续几镜构图雷同问题。

## Capabilities

### Modified Capabilities
- `ai-video-studio/shot-production`: 增加分镜原子化更新保证与并发生成数据完整性规范，修正媒体自愈扫描命名匹配规则。
- `storyboard-visual-composition`: 规范多图合成模式下的提示词轻量化、剥离静态外观描述、重构“同框人物与站位”专职构图职责，并对封闭/室内场景提示词增加室外锚点净化要求。

## Impact

- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 新增 `updateShot` 方法，修复 `_healEpisodeMediaIfNeeded`。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: `ImageGenTask` 与 `VideoGenTask` 改为调用原子化更新。
- `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 重构多图模式下的角色与站位装配逻辑，优化场景保留指令。
- `lib/tools/ai_video_studio/models/studio_models.dart`: 在 `ScenePromptBuilder` 场景底图构建中引入封闭空间净化。
- 自动化测试与工程验证：所有单元测试回归通过，执行 `./scripts/deploy_local.sh` 部署验证。
