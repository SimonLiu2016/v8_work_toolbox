## Why

在当前系统下，当用户创建真人古风实拍电影短剧并生成角色（如“余小白”，16岁矮壮白胖少年）三视图时，生成的角色严重退化为 5~6 岁低幼童子。
经运行时台账与底层追踪，主要根因包括：
1. **Agnes 负向真空**：Agnes 图像 API 不支持 `negative_prompt`，系统组装的负向防低幼违禁词库全部被丢弃；
2. **正向否定词诱发“粉色大象效应”**：正向提示词中存在 `非低幼儿童，非幼童童子，非小娃娃，非低幼矮短` 等否定句，扩散模型的文本编码器无法理解否定语义，反而将“低幼儿童、小娃娃”高权激活为正向生成特征；
3. **原著年龄数字断层丢失**：AI 提炼角色卡时将“十五六岁”留在 `description_zh`，拆解后的 `facial_features_zh`（容貌体态）仅剩“白胖矮壮”，三视图拼接时关键年龄数字丢失；
4. **口语化体态词缺乏人体测量学对冲**：“白胖圆润”、“身材矮胖”在无明确身长骨骼数字约束时，强力激活民间年画娃娃与儿童先验。

本变更旨在建立纯肯定式正向骨骼身量提示词体系、年龄回溯自愈机制与小说解构年龄强保留规则，从根本上杜绝少年与特殊体态角色退化为幼童。

## What Changes

- **纯肯定式正向骨骼身量重构**：彻底清除正向提示词中的所有否定句式（严禁“非低幼儿童、非小娃娃、非低幼矮短”等词进入 Positive Prompt），全部替换为具象肯定表达（如 `16岁青年男子骨架，纵向骨骼身长拉伸，成年人头身比，宽阔肩膀，已度过变声期面容`）。
- **特殊体态（矮壮/微胖）解剖学肯定描述**：将易引发儿童先验的口语化“矮胖”在底层转化为肯定性青年人体解剖描述（`青年写实体态，体魄丰满敦实，肩膀宽厚，成年人骨骼身长比例，非短腿短身`转换为`四肢身长比例舒展，青年男子身长`）。
- **角色年龄回溯与置顶自愈（Age Inheritance）**：在 `CharacterTurnaroundPrompt.build` 中，若 `facial_features_zh` 缺少明确年龄数字，自动从角色的 `description_zh`（总述）中智能提取年龄（如“十五六岁”），并将标准年龄定义强力置顶注入正向 Prompt 最前列。
- **小说全案解构规则强化（Novel Master Extraction）**：在 `AiConstraintEngine` 提炼角色容貌体态（`facial_features_zh`）的 System Prompt 中增加硬约束，强制保留原著的角色年龄/人生阶段定语，严禁在拆解时丢弃年龄。
- **出厂提示词模板与自愈同步**：更新 `StudioPresetStore` 中 `character_age_staging` 的内置默认模板与自愈逻辑，确保新剧集与重置出厂均默认采用纯肯定式规范。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `character-turnaround-sheet`: 扩展三视图提示词契约，要求全年龄骨骼守卫必须使用纯肯定句式（Affirmative Phrasing），禁止正向包含低幼否定词；增加年龄回溯继承机制与人体解剖学身长约束。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`（`CharacterTurnaroundPrompt`、年龄与体态正向表达）
  - `lib/tools/ai_video_studio/models/studio_models.dart`（`character_age_staging` 内置模板默认值）
  - `lib/tools/ai_video_studio/services/studio_preset_store.dart`（出厂模板自愈）
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（`_promptNovelMasterExtraction` 容貌体态保留年龄硬约束）
  - `lib/tools/ai_video_studio/ui/series_page.dart`（生成三视图传参对齐与年龄回溯）
- **APIs & Dependencies**: 无外部破坏性 API 变更，向后兼容现有角色卡。
