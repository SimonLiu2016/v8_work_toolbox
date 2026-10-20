## ADDED Requirements

### Requirement: 场景纯净空镜生图与严格人物抑制

系统 SHALL 在执行任何场景生图（包括单场景主图生成、七方位空间生图与多角度场景包生成）时，对生图提示词进行全链路空镜加固与零人物严格抑制，确保产出的场景资产为纯净的物理置景与环境底板。

1. **肯定式无人空镜专有约束**：系统 SHALL 使用肯定式建筑与环境摄影术语（`completely uninhabited, vacant architecture, deserted, empty background plate, architectural still life, unoccupied room, void of human presence, motionless stillness`）替换或重构传统 `no humans, no people` 等容易被扩散模型注意力机制逆向激活的否定式短语。
2. **首尾双重夹逼结构（Prompt Sandwiching）**：系统 SHALL 将肯定式空镜背景板约束分别注入至正向 Prompt 的最前端（最高注意力权重区）与最末端（收口固化区），将环境细节与镜头视角包裹在中间。
3. **生图提示词人物实体自动清洗（Scrubbing）**：系统 SHALL 在将 `basePrompt` 送往图像生成模型前，自动过滤与清洗其中包含的人称代词、角色称谓、人物实体名词与交互动作词汇（如 `human, people, person, crowd, man, woman, character, figure, pedestrian, someone, vendor, monk, soldier, sitting, walking, talking` 等），将其替换或降级为纯物理构件与环境特征。
4. **适配器层负向词透传与保全**：所有图像生成适配器（包括 Agnes、SenseAudio 以及 OpenAI 兼容协议适配器）在向底层服务发起生图请求时，SHALL 完整组装并传递包含人物抑制词库的 `negative_prompt` 参数，不得静默丢弃。

#### Scenario: 场景提示词首尾夹逼与肯定式构建

- **WHEN** 用户为某场景触发单视角或批量七方位生图
- **THEN** 系统组装的正向生图 Prompt 头部必须包含 `empty background plate, completely uninhabited, vacant architecture`，尾部必须包含 `unoccupied space, zero people, architectural stillness, deserted room`，且不得包含 `no humans` 等具有反向激活风险的敏感词根

#### Scenario: basePrompt 自动剥离人物实体词汇

- **WHEN** 场景的原始英文 Prompt 包含如 `"bustling street with pedestrians and shopkeeper talking"` 等带有人物活动与角色的描述
- **THEN** 经过空镜清洗器后，生图请求中的实际描述将被安全过滤为纯环境置景（例如 `"traditional street with shopfronts and architectural details"`），消除人物实体引导

#### Scenario: 底层图像适配器负向词全透传

- **WHEN** 系统通过 Agnes、SenseAudio 或 OpenAI 兼容图像适配器生成场景空镜
- **THEN** 发往 API 接口的 HTTP 请求体中 SHALL 包含 `negative_prompt` 字段，且内容包含 `human, people, person, crowd, man, woman, face, character, figure, silhouettes, body`
