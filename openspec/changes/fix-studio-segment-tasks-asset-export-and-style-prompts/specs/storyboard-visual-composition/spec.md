## ADDED Requirements

### Requirement: Segment task isolation and ID compatibility

系统在从 AI 拆镜响应中反序列化分镜片段（`StudioSegment`）时，SHALL 兼容解析 `id` 与 `segment_id` 两种键名，若仅提供数字标号则自动转为 `seg-<N>` 格式，保证每个片段拥有唯一非空标识。
在查询分镜任务状态（`tasksForShot`）时，系统 SHALL 严格仅匹配分镜级任务类型（`frame` 关键帧、`video` 单镜视频），MUST NOT 将片段级任务（`segment`）与单镜任务混淆，防止片段生成触发单镜缩略图的加载动画。

#### Scenario: 片段视频生成不触发单镜缩略图转圈
- **WHEN** 用户点击某个片段的「重新生成」或「生成片段」按钮
- **THEN** 仅该片段卡片的组头操作区展示进度转圈指示器
- **AND** 该片段内各分镜的缩略图及其他片段卡片均保持非运行态，不出现全局转圈

#### Scenario: 兼容 AI 拆镜的 segment_id 字段
- **WHEN** AI 拆镜服务返回包含 `segment_id: 1` 结构的片段列表
- **THEN** 反序列化得到的片段对象具有合法的唯一非空 `id`
- **AND** 多个片段之间不会因 ID 为空字符串而发生状态覆盖与串扰

### Requirement: Micro-texture style baseline and anti-AI-glaze suppression

系统在组装关键帧提示词（`PromptAssembler`）时，SHALL 采用基于物理微质感与电影级漫反射的画风基线替代通用的高光磨皮词汇（如 `masterpiece, best quality`），并在默认负向提示词中显式压制 AI 塑料感、蜡像感与 3D 玩偶脸（如 `plastic skin, smooth doll, airbrushed, wax figure, 3d render doll, uncanny valley`），确保角色生成具备统一且自然的古风/现实材质质感。

#### Scenario: 组装带微质感锁与防塑料感的提示词
- **WHEN** 用户或后台任务触发分镜关键帧生成
- **THEN** 组装出的正向提示词包含皮肤微质感、漫反射与胶片光影约束
- **AND** 负向提示词包含防塑料人脸、防假光滑皮肤与防蜡像感的抑制约束

### Requirement: Shot video generation context enrichment and duration adjustment

系统在触发单镜视频生成（`VideoGenTask`）时，SHALL 将该分镜的视觉动作与剧情描述上下文（`promptZh`）随关键帧底图一同提交给视频模型，避免纯静态底图导致的动作盲目性。
系统在分镜卡片上 SHALL 允许用户查看并调节分镜的目标生成时长，提交时按当前激活视频模型的能力档位（如 4s、6s、8s、10s、12s 等）进行合法性吸附。

#### Scenario: 单镜视频任务携带动作意图上下文
- **WHEN** 用户触发单镜视频生成任务
- **THEN** 提交给底层的视频生成请求（`VideoGenRequest`）中包含该镜的动作意图（`promptZh`）与运镜指令
- **AND** 视频生成时长符合当前选择的档位要求
