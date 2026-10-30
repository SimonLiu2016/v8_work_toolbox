## Context

当前短视频工坊中，生成链路依赖 `styleTokens`（英文画风）与 `worldview`（中文世界观叙事）。然而：
1. `worldview` 仅作为用户界面展示大纲，从未注入实际生图提示词中；
2. `styleTokens` 在 IP 主库角色三视图 (`CharacterTurnaroundPrompt`)、道具图生成中被遗漏；
3. 生图大模型缺乏对角色全身下半身服饰的强先验约束，默认抽样现代服装概率，导致玄幻题材角色出现沙滩裤等穿帮问题；
4. 角色卡「生成 Prompt」将制作类型写死为 `'drama'` 且无世界观上下文。

详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 建立结构化「时代与题材锁」体系 `VisualEraGenre`，涵盖仙侠修真、古装武侠/穿越、现代都市豪门、科幻异能、末日废土、未来科幻/赛博、异世界奇幻等核心题材；
- 每个题材预设正向服饰锚点（覆盖下半身形制）、环境/材质锚点与排他负向词典（抑制时代穿帮物）；
- `StudioSeries` 新增 `eraGenre` 字段，兼容旧存档；
- 改造 `CharacterTurnaroundPrompt` 与 IP 主库生图链路（角色三视图、道具图、场景图），全面接入 `styleTokens` 与题材锁的正反向词典；
- 改造角色 Prompt 翻译与小说导入提炼大模型指令，动态注入真实制作类型与世界观题材。

**Non-Goals:**
- 不替换已有的底层文生图适配器（如 SiliconFlow / SenseAudio）；
- 不修改已经生成并落盘的历史图片文件；
- 不强制要求单集分镜中的每个微动作都重复全量追加题材服饰（分镜侧已有角色卡正面图 reference 约束）。

## Decisions

### 1. 结构化时代题材定义：`VisualEraGenre` 预设知识库
- **选择**：在 `lib/tools/ai_video_studio/models/studio_models.dart`（或专属领域服务）中定义不可变类 `VisualEraGenre`，提供静态预设表与查找方法 `VisualEraGenre.fromId(String? id)`。
- **预设清单**：
  - `xianxia`: 仙侠修真 / 东方玄幻
  - `ancient_costume`: 古装武侠
  - `ancient_transmigration`: 古装穿越
  - `modern_urban`: 现代都市豪门
  - `sci_fi_superpower`: 科幻异能 / 都市异能
  - `wasteland`: 末日废土 / 生存朋克
  - `cyberpunk_sci_fi`: 未来科幻 / 赛博朋克
  - `isekai_fantasy`: 异世界 / 西方奇幻
- **备选方案对比**：
  - *方案 A（采用）*：内置高精中英预设，用户界面直接点选中文胶囊芯片，底层直接挂载标准英文词。简单、防穿帮效果最稳定。
  - *方案 B*：让用户在自由文本框输入英文提示词。缺点：非专业用户不了解 SD 提示词工程，极易漏掉下半身及排他负向词。

### 2. 角色三视图分层提示词合成架构 (Layered Turnaround Prompt)
- **选择**：重构 `CharacterTurnaroundPrompt.build`，参数扩展支持 `styleTokens` 与 `VisualEraGenre? eraGenre`：
  - **正向顺序**：
    1. 三视角布局与一致性约束（Layout & Identity）；
    2. 题材服饰正向锚点（若当前题材有服饰锁，如 `traditional flowing Hanfu robes, broad sleeves...`）；
    3. 角色本征 Prompt；
    4. 全局风格锁（`styleTokens`）；
    5. 白底与清晰构图约束。
  - **负向顺序**：
    1. 三视图排他（单人、无多余肢体、无标签）；
    2. 题材排他违禁词（古代题材强力剔除 `modern clothes, shorts, t-shirt, jeans, sneakers, wristwatch...`）；
    3. 基础画质排他（低质、畸变、文字水印）。

### 3. IP 主库道具与场景图生成闭环
- **道具图**：调用 `adapter.generate` 时，拼接 `eraGenre?.propMaterialTokens`、道具英文 Prompt 与全局 `styleTokens`，负向注入题材排他词与纯白底无杂质约束；
- **场景图**：叠加题材环境锚点与全局 `styleTokens`，负向排除时代冲突建筑物。

### 4. 角色 Prompt 翻译与小说提炼大模型指令升级
- **角色 Prompt 翻译**：`AiConstraintEngine.promptTranslation` 新增参数 `worldview` 与 `eraGenre`，`_CharacterEditDialog` 传入当前剧集的真实 `productionType`（而非硬编码 `'drama'`）；
- **小说全案提炼 (Pass 1)**：大模型 system prompt 增加题材识别指令，输出 JSON 增加 `era_genre` 字段。若小说为修仙/玄幻，大模型自动选择 `xianxia`，并在提取角色外貌时主动补齐道袍/古装细节。

## Risks / Trade-offs

- **[Risk] 时代服饰词过于强势，覆盖了角色独特的服装颜色或特征** → **Mitigation**: 时代服饰词放在角色描述之前作为「大品类与年代锚点」，角色的具体颜色、材质与微特征紧随其后（如“月白色内衬、玄色长袍”），大模型会以角色特征词具体特化。
- **[Risk] 旧剧集存档未设置 `eraGenre` 产生空指针** → **Mitigation**: `StudioSeries.eraGenre` 默认为空字符串 `''`，`VisualEraGenre.fromId` 对空串或未识别 key 返回 `null`（保持向后兼容，不产生额外副作用）。
- **[Risk] 负向词过长导致生图引擎超限截断** → **Mitigation**: 时代排他词控制在 15~20 个核心穿帮高频词之内，由 `PromptAssembler` 统一去重与截断保护。
