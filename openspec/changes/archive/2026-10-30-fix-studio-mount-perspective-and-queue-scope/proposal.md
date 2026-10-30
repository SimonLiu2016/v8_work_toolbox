## Why

用户在 AI 视频工坊执行整场视频生成时，遇到了三项严重阻碍成片质量与操作直觉的异常：
1. **物理构图严重崩坏与双重克隆人脸**：坐骑状态（如大黑驴）被无差别赋给分镜内所有角色，导致楼上窗框角色被提示词要求“身处三楼窗框同时骑在大黑驴上”；且场景静态高度标签强行覆盖了机位仰俯与视线朝向，导致街面仰拍镜头被反向编译为俯拍长街，AI 图像模型在物理冲突下直接分裂出两个余小白。
2. **视频生成模式静默突变与素材丢失**：用户在界面中配置或预期为 `reference` 模式的分镜，在点击“生成整场视频”生成关键帧后，因 `auto` 策略被静默提升为 `keyframe` 模式，导致角色参考图数组被清空，视频生成与最新角色素材断联。
3. **任务抽屉跨剧集全量堆叠与时空错位**：云端任务列表直接读取全量历史台账，未按当前剧集与集号隔离。当剧本改编或分镜增删引起镜号重排时，用户在队列中点击的“分镜 3 视频”实际是历史批次的旧请求，呈现出“请求体与界面配置不一致”的严重错觉。

为了彻底消除荒诞构图、保障生成模式确定性并让任务回溯准确可信，必须立项此项规范并予以系统性修复。

## What Changes

1. **实体级坐骑绑定与高低位隔离**：
   - 重构 `_buildMultiCharacterStaging` 与坐骑编译逻辑，坐骑状态（`mount_or_vehicle`）仅与真正骑乘的 `characterId`（或正文明确包含骑乘动作的实体）绑定，严禁向同框配角或高空窗台角色广播。
   - 彻底重构 `compileGazeAndEyeline` 的优先级：明确 `cameraAngle`（`low_angle`/`high_angle`）和 `gazeDirection` 为主观镜头核心指令，其优先级绝对高于静态场景的 `elevationLevel`。杜绝街面仰拍主角被场景层级误杀编译为向下俯拍。
2. **分镜视频模式确定性保护与图生视频提示词收敛**：
   - 确立分镜模式显式选择的最高优先级：若分镜显式指定 `reference`，即便已生成本地关键帧，也绝不强行切换为 `keyframe`；对于 `auto` 模式，增加对用户显式素材意图的保护。
   - 在 `keyframe` 首尾帧图生视频模式下，优化对正文提示词的净化，收敛易引发模型在画面中重新绘制克隆角色的冗余同框站位描述。
3. **任务抽屉与云端台账作用域隔离与时间批次展示**：
   - `_CloudTaskSection` 增加 `seriesId` 与 `episodeId` 作用域过滤，默认仅呈现当前剧集当前集所关联的任务。
   - 在任务卡片（`_CloudTaskTile`）中增加生成时间（年月日时分秒）与对应分镜的简要动作/对白摘要，彻底杜绝历史批次镜号位移导致的查看错位。

## Capabilities

### Modified Capabilities

- `ai-video-studio/shot-continuity`: 约束坐骑与角色的精确归属关系，禁止全镜头广播；确立机位俯仰角与视线朝向对场景高度标签的最高仲裁权。
- `ai-video-studio/shot-production`: 确立分镜生视频模式的确定性判定规则，杜绝静默篡改模式；首尾帧模式下收敛提示词避免双角色克隆。
- `ai-video-studio/segment-production`: 约束任务台账与队列抽屉的数据展示边界，强制按剧集/集号上下文隔离并标明生成时间。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart` (坐骑实体归属过滤、机位仰俯优先级修复、提示词收敛)
  - `lib/tools/ai_video_studio/models/studio_models.dart` & `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` (模式判定与素材保护)
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart` (任务抽屉上下文过滤与任务卡片展示增强)
- **Dependencies**: 无新增三方依赖。
- **Data Compatibility**: 数据模型完全向后兼容，历史台账与剧集分镜数据无需破坏性迁移。
