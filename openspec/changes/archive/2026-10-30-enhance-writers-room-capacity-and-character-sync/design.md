## Context

当前编剧研讨室（`WritersRoomDialog`）与约束引擎（`AiConstraintEngine`）在长文改编短剧时存在集数受限（30 集封顶）与人物/关系设定脱节的问题。背景与动机详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 在 `AiConstraintEngine.extractWritersRoomMaster` 中实现大模型通读后的单季集数智能测算（`recommended_episode_count`、`episode_count_reason`）与结构化人物画像、人物关系图谱提取。
- 升级 `_SchemaValidators.writersRoomMasterExtract` 校验与归一化逻辑，确保推荐集数、角色设定与关系矩阵即使在 LLM 返回轻微偏离时也能自愈回落。
- 增强 `planWritersRoomSeasonBeats` 提示词，支持 60~100+ 集规模的长篇短剧分集大纲连贯生成与悬念断章。
- 重构 `WritersRoomDialog` 的篇章控制交互：支持一键采纳 AI 推荐集数、常用短剧档位（12/24/60/80/100）及自由输入任意集数。
- 在 `WritersRoomDialog` 界面直观呈现角色画像（定位、性格、外貌）及关系矩阵，并提供「同步角色至 IP 库」动作，自动构建或安全合并 `CharacterCard` 并持久化到 `StudioProjectManager`。

**Non-Goals:**
- 不改变底层小说库（`NovelDatabase`）的存储格式或阅读器渲染。
- 不在研讨室阶段立即并发调用生图 API，仅完成角色卡立绘 Prompt 与特征沉淀，生图由后续资产工坊按需触发。

## Decisions

### 1. 约束提示词与数据契约扩展
- **契约定义**：
  - `recommended_episode_count`: int（建议 60~120 集，视原著体量动态给出）
  - `episode_count_reason`: string（篇幅及三幕戏剧弧光推荐依据）
  - `characters`: List of `{"name", "role", "personality", "appearance_features", "motivation", "visual_prompt"}`
  - `character_relations`: List of `{"from", "to", "relation_type", "description"}`
- **容错校验**：在 `_SchemaValidators.writersRoomMasterExtract` 中，若 LLM 未提供推荐集数，根据文本长度自动回落（如 >20000 字回落为 80 集，否则 24 集），确保下游 UI 永不崩溃。

### 2. 集数选择器与交互流重构
- 传统下拉框 `[8, 12, 16, 20, 30]` 升级为复合控制：
  - 若 AI 输出了推荐集数，显示高亮芯片按钮：`💡 AI 推荐: X 集 (采纳)`；
  - 核心档位快捷选择：`[12, 24, 60, 80, 100]`；
  - 自定义集数：点击可弹出快速输入数字对话框（限制 1~500 集），支持任意长剧集规划。

### 3. IP 资产库角色安全合并策略
- 在同步角色至 `StudioProjectManager.saveCharacter` 时：
  - 先调用 `_manager.listCharacters(seriesId)` 获取剧集已有角色；
  - 若已存在同名角色（忽略空白大小写）：复用已有 `id`，保留原有的 `referenceImages`（手绘/实拍参考图）、`faceAnchorPath`（脸模锚点）与 `ttsVoiceId`，将新提炼的性格与外貌特征增量更新到 `descriptionZh` 与 `basePromptPositive`；
  - 若不存在：生成新 `CharacterCard`，填充基础外貌描述、默认形态、别名与提取出的提示词。

## Risks / Trade-offs

- **[Risk]** 规划超长集数（如 100 集）时单次 LLM 生成超时或超出 token 限制。
  - **Mitigation**：在 `StudioAiTask.writersRoomSeasonBeats` 中设置精炼的输出字段（重点在于单集核心危机 conflict、登场角色与集尾 hook），并保持 `timeout` 为 240 秒；大模型按压缩节拍输出，确保 100 集 JSON 在 4k~8k token 范围内紧凑完成。
- **[Risk]** 角色同名但身份不同，或者角色重命名导致重复写入。
  - **Mitigation**：以规范化角色名（`name.trim()`）作为主键检索，同步前提示用户将同步的角色数量，并在同步后弹窗或 SnackBar 给出明确反馈。
