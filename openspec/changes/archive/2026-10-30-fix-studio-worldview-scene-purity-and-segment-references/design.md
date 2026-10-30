## Context

在 AI 视频工坊制作流中，三处原本独立的状态和数据通道产生了边界脱节：
1. **全局会话与组件状态隔离**：`StudioSession` 仅用引用/ID 比较判断新项目，忽略了同一项目的属性就地变更，导致 `SeriesPage` 切 Tab 时读入未更新的陈旧剧集数据。
2. **场景语义受人物叙事污染**：小说解构阶段未明确隔离“角色动态”与“物理空间”，模型直接抓取剧情对白场景描写；生图阶段亦未注入反向人类排他锁，致使场景图频频出现非预期人物。
3. **能力矩阵与本地历史配置冲突**：规整层设计为“持久化声明优先”，但由于旧版写入了默认值 `1`，阻断了支持 8 张参考图的 Agnes 视频模型正常进行多图大段合成。

## Goals / Non-Goals

**Goals:**
- 修复 `StudioSession` 的剧集更新机制与 `SeriesPage` 监听，保证世界观、时代题材与风格词就地修改后跨组件实时一致。
- 升级小说主库解构 Prompt 与 Schema，确保场景空间描述纯净无人物；在生图层全面注入正反向纯空间与消人约束，并提供一键多视角/全景组图生成能力。
- 升级 Agnes 视频能力矩阵声明至 8 张，并在解析器中增加对旧配置残留的智能自愈升级；打通 `SegmentVideoGenTask` 到 `AgnesVideoAdapter` 的多参考图传输。

**Non-Goals:**
- 重构角色卡与道具卡的生图流程。
- 变更云端大模型的通信底层或引入外部依赖。

## Decisions

### 1. 修复 `StudioSession.select` 与就地刷新 `updateSeries`

- **现状问题**：`if (series?.id == next?.id) return;` 导致同项目属性更新被全盘丢弃。
- **技术决策**：
  - 修改 `StudioSession.select(StudioSeries? next)`：若 `series?.id == next?.id`，更新 `series = next` 并触发 `notifyListeners()`，**保留当前选中的 `episode`**（仅在剧集 ID 发生切换时才清空 `episode`）。
  - 新增 `updateSeries(StudioSeries next)`，提供语意清晰的就地更新接口。
  - 在 `SeriesPage` 中使用 `ListenableBuilder` 绑定 `widget.session`，确保用户修改时代题材（`eraGenre`）或世界观后，Tab 切换与切回时立即呈现最新选择。

### 2. 场景空间纯净化与多视角组图套件

- **技术决策**：
  - **小说解构层**：在 `_promptNovelMasterExtraction` 中增加强硬负向约束：`description_zh` 必须为“纯净空镜空间建筑、陈设与光影，严禁描写任何人物、走动与情节动态”；`prompt_en` 必须输出无人物的纯空间 Prompt。
  - **生图适配层**：在 `_SceneEditorSheetState._generateImage` 中，正向词追加 `empty scene, no humans, pure architectural scenery, vacant interior`，负向词强制覆盖 `human, people, person, crowd, man, woman, face, character`。
  - **多角度组图套件**：在 `_SceneEditorSheet` 中提供「生成多角度场景包」按钮，依次通过微调运镜视角词（Establishing Wide Panoramic, Eye-Level Main View, Reverse Angle, Interior Detail Close-up）生成 4 张成套参考图，写入场景资产库。

### 3. 能力矩阵历史配置自愈与 Agnes Reference 模式打通

- **技术决策**：
  - **能力预设与默认值**：将 `MediaCapabilityDefaults.agnes` 与 `MediaCapabilityPresets.agnesVideo25` / `agnesVideo25Flash` 中的 `maxReferenceImages` 调整为 `8`。
  - **自愈解析规则**：在 `MediaCapabilityResolver.resolve` 中，当本地已保存的 `declared.maxReferenceImages` 小于官方内置预设时，自动取预设的高上限值（`max(declared, preset)`），防止用户旧配置持续阻断 4 张参考图。
  - **大段生成显式绑定 reference 模式**：在 `SegmentVideoGenTask` 中创建 `VideoGenRequest` 时，显式传 `mode: AgnesVideoMode.reference`；并在 `AgnesVideoAdapter` 中支持将所有参考图编码为 `images: [...]` 提交云端。

## Risks / Trade-offs

- **[多角度生图并发消耗]** → 提供单张生成与多角度组图两档按钮，由用户主动选择是否一次性生成 4 视角，避免无意消耗过多积分。
- **[历史场景描述已污染]** → 在场景编辑弹窗中提供一键“AI 重新纯净化描述”，允许用户把已有小说场景中的人物描述一键清洗掉。
