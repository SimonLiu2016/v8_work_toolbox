## Context

详见 `proposal.md`。工坊在过去迭代中遗留了针对 2022~2023 年 SD1.5/CLIP 文本编码器的历史包袱，导致大量角色、服装与场景被强制翻译为碎片化的英文 Prompt，并堆砌了诸如 `Unreal Engine 5 render, Octane render` 等相互冲突且过时的英文咒语。同时，小说提炼与分场剧本提示词受低俗短剧刻板模板（“前3秒危机受辱打脸”）严重绑架，不仅抹杀了原著松弛腹黑的主角神韵（拟出《长街受辱》等违和标题），且丢弃了网络小说最核心的【内心独白 / OS】，造成剧本与后续分镜支离破碎、语义严重失真。

## Goals / Non-Goals

**Goals:**
- **重构剧本改编提示词体系**：彻底清洗低俗短剧刻板词汇，建立原著人物性格保护机制，原生支持 `inner_voice`（角色内心独白/OS）；
- **剧本工作台体验升级**：输出规范连贯的文学分场剧本，清晰呈现角色内心 OS 与外部对白；
- **Prompt 全面切回原生纯中文导演语言**：重构 `PromptAssembler`，移除英文咒语堆叠，生成发往国产大模型（Agnes、即梦、可灵等）的高聚焦、所见即所得的中文导演镜头指令；
- **音画分流规范化**：确保带有内心独白或台词的分镜在画面上保持自然从容的闭口神态，台词沉淀至音频轨，杜绝汉字乱码与嘴型畸变。

**Non-Goals:**
- 不破坏 SQLite 数据库与既有项目存档格式（向后兼容既有工程）；
- 不移除通用海外模型适配器的基础网络能力（但提示词组装不再默认注入过时英文咒语）；
- 不变更视频任务底层状态机与轮询生命周期（Ledger 与 Recovery 机制保持不变）。

## Decisions

### 1. 提示词去“短剧刻板偏见”与“原著调性自适应”
- **决策**：在 `ai_constraint_engine.dart` 中，重构 `_promptNovelDramaChapterAdaptation`, `_promptScreenplayGeneration`, `_promptNovelEpisodeSegmentation`：
  - 剔除 `爆款竖屏短剧`、`前 3 秒必须爆发核心冲突`、`开局抓手：核心危机` 等刻板导向词；
  - 增加【原著人物性格与爽点自适应法则】：明确要求忠实提取原著中主角的言语风格与动机，严禁将主角的主动反击、幽默戏谑曲解为受辱或屈服；
  - 剧本标题生成规则：结合地点、动作与关键转折，保持小说原汁原味的文学质感（如《青驴载狱卒，天降九年修为》）。

### 2. 剧本节拍模型原生支持【内心独白（OS）】
- **决策**：
  - 在 `DramaBeat` 中增加 `voiceType` 字段（类型为 `UtteranceVoiceType`，可选 `dialogue`, `innerVoice`, `narration`，默认 `dialogue`）；
  - `_promptScreenplayGeneration` 与 `_promptNovelDramaChapterAdaptation` 输出的节拍中，允许大模型为思考/吐槽/心声标记 `"voice_type": "inner_voice"`；
  - `screenplay_panel.dart` 中的 Markdown 导出器（`_exportToMarkdown`）升级：
    - 对白标记为：`对白（姜七夜）：两个大男人喝酒有啥意思。`
    - 心声标记为：`姜七夜（内心 OS）：余小白，天人居少东家... 不妨约他姐出来坐坐。`

### 3. `PromptAssembler` 全面转向纯中文导演镜头语言
- **现状**：`compileShot` 和 `compileSegment` 使用了中英混杂模式，硬编码了 `cinematic lighting, photorealistic 8k, Phase 1 [0-50% / Initial Framing & Action]`，并拉取了英文字段 `character.basePromptPositive` 和 `scene.promptEn`。
- **决策**：
  - 彻底移除 `Phase 1`, `Phase 2`, `Subject: ...`, `Environment: ...` 等英文套皮；
  - 优先拉取角色的纯中文外貌与服装（`character.descriptionZh`, `character.facialFeaturesZh`, `character.defaultAttireZh`）和场景纯中文置景（`scene.descriptionZh`）；
  - 统一编译为纯中文结构化导演指令，例如：
    ```
    【镜头景别与运镜】全景平视跟随，长刀自下而上横挑
    【空间与光影】寒阳城长街，黄昏斜阳穿透长街，远处朱漆酒楼天人居矗立
    【出场主体】姜七夜（二十岁出头，剑眉英挺，身姿挺拔，着暗青色巡城卫制服），骑乘高大青驴
    【动作叙事】余小白自三楼凭栏暴怒砸下金黄油亮的百草烤鸡；姜七夜单手拔长刀出鞘，刀尖贯穿整只烤鸡，大口撕咬咀嚼
    【声音与画面约束】[角色心声/画外音: "高空抛物，放前世拘你半个月"，画面主体保持闭口神态与从容微表情，无画内文字]
    ```
  - 发往 Agnes 试炼场、批量任务队列与视频适配器时，直接使用干净纯粹的中文 Prompt，彻底根除英文词重复堆叠、冲突与 Token 挤压。

## Risks / Trade-offs

- **[Risk] 海外开源老旧模型（如原生 SD 1.5）可能对中文 Prompt 理解有限**
  - → *Mitigation*: 当前工坊的核心生产环境全面基于国产原生多模态主力模型（Agnes、即梦、可灵、海螺）；若用户选择 SD 1.5 等老旧开源模型，可通过提示词翻译辅助插件按需处理，绝不牺牲 95% 以上现代国风生产管线的纯粹度。
- **[Risk] 现有本地剧集如果已经存有旧英文 Prompt，重算时是否会出现不兼容**
  - → *Mitigation*: `PromptAssembler` 内部优先取中文属性，中文为空时才兜底回退旧字段，老工程无缝读取，随时点击重新组装即可自动升级为最新原生中文 Prompt。
