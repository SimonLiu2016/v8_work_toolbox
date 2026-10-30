## Context

在长篇连续剧与小说推文制作中，角色会有换装（宗门常服、玄铁重战甲、隐秘夜行衣、战损服饰）与年龄时期演进（少年期、成熟掌门期、老年仙尊期）。此前系统仅支持角色卡持有一张全局三视图（`turnaround.png`），当分镜需要不同服装或年龄时，Prompt 描述与参考底图发生严重冲突，导致脸模失真或服装还原失败。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 将 `CharacterVariation` 升级为拥有独立三视图（`turnaroundPath`）与参考图列表的资产实体。
- 为子形态生成三视图时，自动注入角色基准三视图（`turnaround.png`）作为参考图，实现面部五官与艺术风格的强一致性继承（Face Identity Inheritance）。
- 在形态列表 UI 中提供各形态专属三视图的生成（支持标准/Q版比例）、高清大图预览、删除与一键入资产库。
- 在 `StudioShot` 中支持镜头级绑定角色具体形态（`characterVariations: Map<String, String>`），并在分镜看板卡片（`_ShotCard`）提供角色与形态联动下拉选择。
- 在关键帧生图任务（`ImageGenTask`）中实现动态底图路由：优先读取选定形态的专属三视图，缺失时平滑回落默认三视图。

**Non-Goals:**
- 不引入重度的三维建模或 Mesh 变体系统，保持基于 Diffusion 生图模型与 ControlNet/Image-to-Image 的高效轻量工作流。
- 不强制要求每个形态都必须有三视图；未生成三视图的形态依然能依赖文本差异词正常生图。

## Decisions

### 1. 形态三视图命名与存储结构
- **决策**：
  - 基准默认形态保留为 `turnaround.png`（旧版数据与向后兼容完全保持）。
  - 各子形态独立三视图落盘为 `turnaround_${variation.id}.png`，存放在该角色的专属目录 `characters/<character-id>/` 下。
  - `CharacterVariation` 增加可选字段 `turnaroundPath: String?` 与 `referenceImages: List<String>`。
- **替代方案考虑**：
  - 为每个形态建立子文件夹：增加文件层级与路径解析开销，单层目录以前缀命名更轻量直观。

### 2. 生成形态三视图时的脸模继承机制
- **决策**：
  - 用户为某形态点击「生成三视图」时，检查角色目录下是否存在默认三视图 `turnaround.png`（若无则检查 `character.referenceImages.first`）。
  - 若存在，自动将其作为 `referenceImages` 传递给生图适配器，并在 Prompt 中加入同人面部与骨骼约束：`same character facial identity, identical facial features as reference image, wearing [outfit description]`。
  - 生成参数同样支持选择「标准比例 (7~8头身)」或「Q版萌系 (2.5头身)」。
- **效果**：保证同一个主角在少年期、战甲期、夜行衣期保持“同一张脸”，彻底解决换装即换人的行业痼疾。

### 3. 分镜模型与镜头级形态选择
- **决策**：
  - `StudioShot` 增加 `Map<String, String> characterVariations` 字段，存储当前镜头中角色的形态映射（`{"char_id": "var_id"}`）。
  - 在 `storyboard.json` 序列化中保存该字段，旧版 JSON 缺少该字段时默认为空 Map。
  - 解析优先级：`shot.characterVariations[charId]` ➔ `episode.variationOverrides[charId]` ➔ `character.activeVariation` ➔ 默认基础形态。
  - `_ShotCard` UI 交互：在场景选择器旁增加 `角色:` 和 `形态:` 下拉菜单，选定后触发 2 秒防抖自动重组 Prompt 并落盘。

### 4. 关键帧任务（ImageGenTask）多级动态底图路由
- **决策**：
  - `ImageGenTask._referenceImages` 改造：根据镜头指定的 `variation`，优先检查是否存在 `turnaround_${variation.id}.png`；
  - 若存在，将其作为角色首选参考底图传递给生图引擎；
  - 若该形态未生成专属三视图，自动回退使用 `turnaround.png`；若亦无，回退使用 `character.referenceImages.first`。

## Risks / Trade-offs

- **[Risk] 生图适配器在接收参考图后可能忽略新服装描述，依然画出参考图中的旧道袍**
  - **缓解措施**：在 `PromptAssembler` 中将形态差异词（新服装/新特征）置于高权重位置，并显式注入负向词（如生成战甲时，负向词自动屏蔽旧道袍的 `robes, casual clothes`）。
- **[Risk] 删除形态时磁盘文件残留**
  - **缓解措施**：在角色卡删除形态或形态更新方法中，若形态被移除，同步检查并安全删除 `turnaround_${variation.id}.png`。
- **[Risk] 旧版工程分镜数据升级兼容**
  - **缓解措施**：`StudioShot.characterVariations` 默认为空 Map，所有读取逻辑做空值保护，无感知向后兼容。
