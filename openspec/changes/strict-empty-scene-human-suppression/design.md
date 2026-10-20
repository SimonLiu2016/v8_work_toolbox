## Context

当前场景生图（单场景主图、七方位空间生图、多角度场景包）虽然定义了 `ScenePromptBuilder`，但仍偶发带人物问题。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- **彻底杜绝人物潜变量激活**：将现有的“否定式”词汇（`no humans, no people`）全面替换为扩散模型更易遵循的“肯定式无人空镜专有术语”（`completely uninhabited, vacant architecture, deserted, empty background plate, architectural still life`）。
- **首尾双重夹逼（Prompt Sandwiching）**：在 Prompt 头部（最高注意力权重）与尾部（收尾锚点）分别锁死纯净空镜底板，包裹并约束中间的具体视角与陈设描述。
- **提示词人物实体与动作自动净化（Sanitization）**：在生图前对 `basePrompt` 进行正则清洗，自动剥离、替换人称代词、职业称谓、人群与互动动作词。
- **底层 Adapter 负向词全链路打通**：在 `SystemAiImageAdapter`、`SenseAudioImageAdapter` 等适配器中补齐 `negative_prompt` 组装与传递，确保无论后端是哪种协议，负向抑制词库均能正确触达。

**Non-Goals:**
- 不影响角色（CharacterCard）与道具（PropCard）的生图提示词组装逻辑。
- 不引入额外的本地去人物语义分割或重绘（Inpainting）模型，保持轻量高效。

## Decisions

### Decision 1: 使用肯定式无人空镜描述符替代否定式短语
- **背景与原因**：主流文生图模型的文本编码器（CLIP / T5-XXL）基于跨注意力（Cross-Attention）矩阵机制，对否定词（"no", "without"）缺乏真正的布尔逻辑理解，反而会因为注意力击中 "human" / "people" 词根而增加生成人物的概率。
- **方案**：使用专业影视摄影与建筑艺术专有词：
  - 头部正向锁：`empty background plate, completely uninhabited, vacant architecture, zero people`
  - 尾部正向锁：`unoccupied room, deserted scenery, architectural still life, void of human presence, motionless stillness`
- **替代方案考虑**：仅依靠 negative_prompt（不可靠，因为 FLUX、Midjourney、Agnes 等很多模型或服务商不接收或忽略 negative_prompt）。

### Decision 2: 确立首尾双重夹逼 Prompt 拓扑结构
- **背景与原因**：Transformer 架构的序列位置编码对序列两端具有明显的注意偏置（Primacy & Recency Effect）。
- **结构**：
  ```
  [头部: 肯定式空镜背景板锁] + [时代题材与环境材质基调] + [视角机位前缀] + [清洗后的物理陈设细节] + [尾部: 强效无人收尾锁]
  ```
- **效果**：无论用户或小说在中间填写了多么丰富的描述，整个提示词的语义范畴被两端的背景板定位牢牢锚定在“影视后期专用纯净物理空镜底板”。

### Decision 3: 确定性敏感词实体与动作清洗器 (`sanitizeBasePrompt`)
- **实现**：在 `ScenePromptBuilder` 中内置正则清洗函数，对输入的 `basePrompt` 进行全词匹配清洗：
  - 实体与人群词：`human, people, person, crowd, man, woman, boy, girl, figure, character, pedestrian, citizen, guard, soldier, monk, vendor, merchant, someone, anyone, inhabitant`
  - 角色动作词：`walking, sitting, standing, talking, fighting, sleeping, looking, running, waving`
  - 场景氛围词降级：`bustling` → `spacious`, `lively` → `intricate`, `crowded` → `detailed`
- **效果**：即使用户在中文场景中填写了“客栈里食客满座，掌柜正在算账”，翻译清洗后也只会保留“客栈大堂，桌椅摆设，账台算盘”，从源头剔除人物生成信号。

### Decision 4: 修复底层适配器负向提示词透传
- **问题**：`SystemAiImageAdapter` 在 `isAgnes` 分支中直接忽略了 `request.negativePrompt`；`SenseAudioImageAdapter` 也未将 `negative_prompt` 加入请求体。
- **改动**：在 `payload` 组装中统一注入 `negative_prompt`（若存在），同时在 Agnes 的 `extra_body` 与 payload 根节点中同时保留，确保支持负向词的后端能够完整生效。

## Risks / Trade-offs

- **[Risk] 过度清洗导致合理的静物描述受损（例如 "human-scale" 或 "monk robe hanging on wall"）**  
  → **Mitigation**：使用精准单词边界（`\b`）匹配，且仅清洗人物生命体与主体动作，对 "mannequin"、"statue"、"portrait on wall" 等静物予以保留，必要时补充 "empty" 前缀修饰。
- **[Risk] 部分下游第三方 API 对未声明字段严格报错（如某些极简 REST 服务）**  
  → **Mitigation**：仅在 `negativePrompt.trim().isNotEmpty` 时注入该字段，且遵照各供应商官方 API 规范（如 Agnes/OpenAI 的 extra_body 与根属性规范）。
